import Foundation
import CoreBluetooth
import Combine

// MARK: - CoreBluetoothTransport

final class CoreBluetoothTransport: NSObject, BLETransportProtocol {

    // MARK: - Service / Characteristic UUIDs

    static let heartRateServiceUUID             = CBUUID(string: "180D")
    static let healthThermometerServiceUUID     = CBUUID(string: "1809")
    static let hrMeasurementCharUUID            = CBUUID(string: "2A37")
    static let temperatureMeasurementCharUUID   = CBUUID(string: "2A1C")

    // MARK: - Publishers

    private let connectionStateSubject  = PassthroughSubject<BLEConnectionState, Never>()
    private let hrMeasurementSubject    = PassthroughSubject<HRMeasurement, Never>()
    private let temperatureSubject      = PassthroughSubject<TemperatureMeasurement, Never>()

    var connectionStatePublisher: AnyPublisher<BLEConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    var hrMeasurementPublisher: AnyPublisher<HRMeasurement, Never> {
        hrMeasurementSubject.eraseToAnyPublisher()
    }
    var temperaturePublisher: AnyPublisher<TemperatureMeasurement, Never> {
        temperatureSubject.eraseToAnyPublisher()
    }

    // MARK: - Private State

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var reconnectWorkItem: DispatchWorkItem?
    private var isScanning = false

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - BLETransportProtocol

    func startScanning() {
        isScanning = true
        guard centralManager.state == .poweredOn else { return }
        performScan()
    }

    func stopScanning() {
        isScanning = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        connectionStateSubject.send(.disconnected)
    }

    func disconnect() {
        isScanning = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        connectionStateSubject.send(.disconnected)
    }

    // MARK: - Private Helpers

    private func performScan() {
        guard centralManager.state == .poweredOn else { return }
        connectionStateSubject.send(.scanning)
        centralManager.scanForPeripherals(
            withServices: [
                CoreBluetoothTransport.heartRateServiceUUID,
                CoreBluetoothTransport.healthThermometerServiceUUID
            ],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func scheduleReconnect() {
        guard isScanning else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isScanning else { return }
            self.performScan()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
}

// MARK: - CBCentralManagerDelegate

extension CoreBluetoothTransport: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if isScanning { performScan() }
        case .poweredOff:
            connectionStateSubject.send(.error("Bluetooth is powered off"))
        case .unauthorized:
            connectionStateSubject.send(.error("Bluetooth access not authorized"))
        case .unsupported:
            connectionStateSubject.send(.error("Bluetooth not supported on this device"))
        case .resetting:
            connectionStateSubject.send(.disconnected)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard connectedPeripheral == nil else { return }
        central.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionStateSubject.send(.connecting)
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "Unknown Device"
        connectionStateSubject.send(.connected(peripheralName: name))
        peripheral.discoverServices([
            CoreBluetoothTransport.heartRateServiceUUID,
            CoreBluetoothTransport.healthThermometerServiceUUID
        ])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        let msg = error?.localizedDescription ?? "Failed to connect"
        connectionStateSubject.send(.error(msg))
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        if let error {
            connectionStateSubject.send(.error(error.localizedDescription))
        } else {
            connectionStateSubject.send(.disconnected)
        }
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension CoreBluetoothTransport: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            switch service.uuid {
            case CoreBluetoothTransport.heartRateServiceUUID:
                peripheral.discoverCharacteristics(
                    [CoreBluetoothTransport.hrMeasurementCharUUID],
                    for: service
                )
            case CoreBluetoothTransport.healthThermometerServiceUUID:
                peripheral.discoverCharacteristics(
                    [CoreBluetoothTransport.temperatureMeasurementCharUUID],
                    for: service
                )
            default:
                break
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case CoreBluetoothTransport.hrMeasurementCharUUID,
                 CoreBluetoothTransport.temperatureMeasurementCharUUID:
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            default:
                break
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }

        switch characteristic.uuid {
        case CoreBluetoothTransport.hrMeasurementCharUUID:
            if let measurement = try? HRMeasurementParser.parse(data) {
                hrMeasurementSubject.send(measurement)
            }

        case CoreBluetoothTransport.temperatureMeasurementCharUUID:
            if let measurement = try? TemperatureMeasurementParser.parse(data) {
                temperatureSubject.send(measurement)
            }

        default:
            break
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // No action needed; notifications are active once subscribed.
        if let error {
            connectionStateSubject.send(.error("Notification error: \(error.localizedDescription)"))
        }
    }
}
