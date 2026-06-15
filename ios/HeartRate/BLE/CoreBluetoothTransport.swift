import Foundation
import CoreBluetooth
import Combine

// MARK: - CoreBluetoothTransport

/// Production BLE transport. Connects to either device profile and auto-detects
/// which one a peripheral implements (see docs/BLE_CONTRACT.md):
///   - Profile A: standard Heart Rate (0x180D) + Health Thermometer (0x1809)
///   - Profile B: BodyTempSensor custom service (skin/core temp + EDA)
final class CoreBluetoothTransport: NSObject, BLETransportProtocol {

    // MARK: - Service / Characteristic UUIDs

    // Profile A — standard GATT
    static let heartRateServiceUUID             = CBUUID(string: "180D")
    static let healthThermometerServiceUUID     = CBUUID(string: "1809")
    static let hrMeasurementCharUUID            = CBUUID(string: "2A37")
    static let temperatureMeasurementCharUUID   = CBUUID(string: "2A1C")

    // Profile B — BodyTempSensor custom service (base a0b4XXXX-7e9c-4f1a-9a1e-7c0ffeed0001)
    static let bodyTempServiceUUID   = CBUUID(string: "a0b40000-7e9c-4f1a-9a1e-7c0ffeed0001")
    static let bodyTempSkinCharUUID  = CBUUID(string: "a0b40001-7e9c-4f1a-9a1e-7c0ffeed0001")
    static let bodyTempCoreCharUUID  = CBUUID(string: "a0b40002-7e9c-4f1a-9a1e-7c0ffeed0001")
    static let bodyTempEDACharUUID   = CBUUID(string: "a0b40003-7e9c-4f1a-9a1e-7c0ffeed0001")

    /// Every service the app knows how to talk to; used for both scan and discover.
    private static let allServiceUUIDs: [CBUUID] = [
        heartRateServiceUUID, healthThermometerServiceUUID, bodyTempServiceUUID
    ]

    // MARK: - Reconnect tuning

    private static let reconnectBaseDelay: TimeInterval = 1.0
    private static let reconnectMaxDelay: TimeInterval  = 30.0
    private static let connectTimeout: TimeInterval     = 10.0

    // MARK: - Publishers

    private let connectionStateSubject  = PassthroughSubject<BLEConnectionState, Never>()
    private let hrMeasurementSubject    = PassthroughSubject<HRMeasurement, Never>()
    private let temperatureSubject      = PassthroughSubject<TemperatureMeasurement, Never>()
    private let edaSubject              = PassthroughSubject<EDAMeasurement, Never>()

    var connectionStatePublisher: AnyPublisher<BLEConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    var hrMeasurementPublisher: AnyPublisher<HRMeasurement, Never> {
        hrMeasurementSubject.eraseToAnyPublisher()
    }
    var temperaturePublisher: AnyPublisher<TemperatureMeasurement, Never> {
        temperatureSubject.eraseToAnyPublisher()
    }
    var edaPublisher: AnyPublisher<EDAMeasurement, Never> {
        edaSubject.eraseToAnyPublisher()
    }

    // MARK: - Private State

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    /// Identifier of the last peripheral we successfully started connecting to,
    /// so a reconnect can target it directly instead of re-scanning blindly.
    private var lastPeripheralID: UUID?
    private var reconnectWorkItem: DispatchWorkItem?
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var isScanning = false

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - BLETransportProtocol

    func startScanning() {
        isScanning = true
        reconnectAttempt = 0
        guard centralManager.state == .poweredOn else { return }
        performScan()
    }

    func stopScanning() {
        isScanning = false
        // Explicit stop = forget the device, so a later scan can pair a different
        // one. (A transient drop keeps it, see didDisconnectPeripheral.)
        lastPeripheralID = nil
        cancelPendingWork()
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        connectionStateSubject.send(.disconnected)
    }

    func disconnect() {
        isScanning = false
        lastPeripheralID = nil
        cancelPendingWork()
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        connectionStateSubject.send(.disconnected)
    }

    // MARK: - Private Helpers

    private func cancelPendingWork() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
    }

    private func performScan() {
        guard centralManager.state == .poweredOn, connectedPeripheral == nil else { return }

        // Prefer a direct reconnect to the device we were last bonded to this
        // session — faster and avoids grabbing a different nearby strap.
        if let id = lastPeripheralID,
           let known = centralManager.retrievePeripherals(withIdentifiers: [id]).first {
            connect(known)
            return
        }

        connectionStateSubject.send(.scanning)
        centralManager.scanForPeripherals(
            withServices: CoreBluetoothTransport.allServiceUUIDs,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func connect(_ peripheral: CBPeripheral) {
        if centralManager.isScanning { centralManager.stopScan() }
        connectedPeripheral = peripheral
        lastPeripheralID = peripheral.identifier
        peripheral.delegate = self
        connectionStateSubject.send(.connecting)
        centralManager.connect(peripheral, options: nil)
        startConnectTimeout(for: peripheral)
    }

    /// If a connection attempt stalls in `.connecting`, abandon it and retry so
    /// the strap can't get wedged in a half-open state.
    private func startConnectTimeout(for peripheral: CBPeripheral) {
        connectTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectedPeripheral?.identifier == peripheral.identifier else { return }
            self.centralManager.cancelPeripheralConnection(peripheral)
            self.connectedPeripheral = nil
            self.connectionStateSubject.send(.error("Connection timed out"))
            self.scheduleReconnect()
        }
        connectTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CoreBluetoothTransport.connectTimeout, execute: work)
    }

    /// Exponential backoff with jitter, capped — avoids a hot reconnect loop that
    /// drains the battery when a device is simply out of range.
    private func scheduleReconnect() {
        guard isScanning else { return }
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil

        let exponential = CoreBluetoothTransport.reconnectBaseDelay * pow(2.0, Double(reconnectAttempt))
        let capped = min(exponential, CoreBluetoothTransport.reconnectMaxDelay)
        let jitter = Double.random(in: 0...(capped * 0.25))
        let delay = capped + jitter
        reconnectAttempt = min(reconnectAttempt + 1, 16)  // cap exponent growth

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isScanning, self.connectedPeripheral == nil else { return }
            self.performScan()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
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
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        reconnectAttempt = 0
        let name = peripheral.name ?? "Unknown Device"
        connectionStateSubject.send(.connected(peripheralName: name))
        peripheral.discoverServices(CoreBluetoothTransport.allServiceUUIDs)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
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
                    [CoreBluetoothTransport.hrMeasurementCharUUID], for: service)
            case CoreBluetoothTransport.healthThermometerServiceUUID:
                peripheral.discoverCharacteristics(
                    [CoreBluetoothTransport.temperatureMeasurementCharUUID], for: service)
            case CoreBluetoothTransport.bodyTempServiceUUID:
                peripheral.discoverCharacteristics([
                    CoreBluetoothTransport.bodyTempSkinCharUUID,
                    CoreBluetoothTransport.bodyTempCoreCharUUID,
                    CoreBluetoothTransport.bodyTempEDACharUUID,
                ], for: service)
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
            // Subscribe to anything notifiable/indicatable that we recognise.
            if characteristic.properties.contains(.notify) ||
               characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
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
        // Profile A
        case CoreBluetoothTransport.hrMeasurementCharUUID:
            if let m = try? HRMeasurementParser.parse(data) { hrMeasurementSubject.send(m) }

        case CoreBluetoothTransport.temperatureMeasurementCharUUID:
            if let m = try? TemperatureMeasurementParser.parse(data) { temperatureSubject.send(m) }

        // Profile B — BodyTempSensor custom service
        case CoreBluetoothTransport.bodyTempSkinCharUUID:
            if let m = try? BodyTempFrameParser.parseTemperature(data, site: .skin) { temperatureSubject.send(m) }

        case CoreBluetoothTransport.bodyTempCoreCharUUID:
            if let m = try? BodyTempFrameParser.parseTemperature(data, site: .core) { temperatureSubject.send(m) }

        case CoreBluetoothTransport.bodyTempEDACharUUID:
            if let m = try? BodyTempFrameParser.parseEDA(data) { edaSubject.send(m) }

        default:
            break
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            connectionStateSubject.send(.error("Notification error: \(error.localizedDescription)"))
        }
    }
}
