# BLE Contract — Pulse app ⇄ wearable firmware

The single source of truth for what the iOS app expects over BLE and what the
firmware must expose. The app supports **two device profiles** and auto-detects
which one a connected peripheral implements, based on the services it advertises
/ exposes on connect.

> Companion firmware lives in `../BodyTempSensor` (nRF54L15, Zephyr/NCS). Its
> `Firmware/biometric-wearable/src/radio/ble_service.c` is the authority for the
> custom-profile side of this contract — keep the two in sync.

---

## Profile A — Standard GATT (nRF52840 `ble_app_hrs`, LightBlue, generic straps)

Used by the original demo target and any off-the-shelf HR/thermometer device.

| Role | UUID | Format | Notes |
|---|---|---|---|
| Heart Rate **service** | `0x180D` | — | Bluetooth SIG |
| HR Measurement **char** | `0x2A37` | SIG HR Measurement | Notify. 8/16-bit HR, optional RR (1/1024 s), sensor contact |
| Health Thermometer **service** | `0x1809` | — | Bluetooth SIG |
| Temperature Measurement **char** | `0x2A1C` | IEEE-11073 32-bit FLOAT | Notify/Indicate. Optional Type byte → skin/core; a 2nd temp char ⇒ "Site 2" |

Parsers: `HRMeasurementParser`, `TemperatureMeasurementParser`.

---

## Profile B — BodyTempSensor custom service (nRF54L15)

Custom 128-bit service. Base UUID `a0b4XXXX-7e9c-4f1a-9a1e-7c0ffeed0001`; only
the 3rd-from-left group (`XXXX`) varies. Device advertises as **`BodyTempPoC`**.

| Role | UUID (`XXXX`) | Format | Properties |
|---|---|---|---|
| Service | `a0b40000-…` | — | — |
| Skin temperature | `a0b40001-…` | `float32` LE, °C | Read + Notify |
| Core temperature | `a0b40002-…` | `float32` LE, °C | Read + Notify |
| EDA conductance | `a0b40003-…` | `float32` LE, µS | Read + Notify |
| Combined frame | `a0b40004-…` | raw `biometric_frame_t` | Read + Notify |

**Encoding:** each scalar characteristic is one native little-endian IEEE-754
single-precision float (4 bytes). The app decodes with
`Float(bitPattern: UInt32(littleEndian:))` — see `BodyTempFrameParser`.

**The app subscribes to the three scalar characteristics (`0001/0002/0003`), not
the combined frame (`0004`).** The combined frame is a byte-for-byte copy of the
firmware's packed C struct; its layout depends on compiler padding/alignment and
is explicitly a PoC convenience on the firmware side. Relying on the individual
scalar characteristics keeps the contract robust to struct changes. If a future
build versions and serialises the frame explicitly, the app can add a parser for
`0004` then.

Mapping into the app's data model:

| Characteristic | → `Reading` field | → in-app stream |
|---|---|---|
| Skin temp `0001` | `tempSkin` | `TemperatureMeasurement(site: .skin)` |
| Core temp `0002` | `tempCore` | `TemperatureMeasurement(site: .core)` |
| EDA `0003` | `eda` (µS) | `EDAMeasurement` |

> **No heart rate.** The BodyTempSensor has no HR sensor, so on Profile B the app
> persists temperature + EDA only and leaves `heartRate`/`rrIntervals` empty.
> HR-derived warnings (fatigue/HRV) simply won't fire; temperature-based
> overheating and the EDA signal still work. A future combined strap that exposes
> both `0x180D` and the custom service is supported transparently — the app
> subscribes to every recognised service it finds on the peripheral.

---

## Auto-detection

On connect, the app discovers all of: `0x180D`, `0x1809`, and the custom service
UUID. For each service present it subscribes to the recognised characteristics.
A peripheral may implement Profile A, Profile B, or (in future) both — the app
does not need to know in advance.

### Advertising requirement

The app scans **filtered by service UUID** (`scanForPeripherals(withServices:)`)
for efficiency, so a device MUST advertise its primary service UUID for the app
to discover it. For Profile B the 128-bit UUID + complete name don't both fit in
the 31-byte advertising payload, so the firmware puts the **name in the
advertising data and the service UUID in the scan response** — iOS matches the
filter against either. (Firmware: `sd[]` in `ble_service.c`.)

## ANT+ (out of scope for the app)

The BodyTempSensor also broadcasts an ANT+ page (primary link, for Garmin
receivers). The iOS app does not consume ANT+; it only uses BLE. See the
firmware README for the ANT page layout.
