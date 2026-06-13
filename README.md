# Pulse — Heart Rate + Core Temperature Wearable Companion

A consumer-grade iOS app and sync backend for a BLE wearable with a MAX30102 heart-rate sensor and dual temperature sensing, built on an nRF52840 DK running Nordic's `ble_app_hrs` firmware.

The hardware doesn't exist yet — everything works end-to-end against simulated data via **Demo Mode** so you can develop and demo now, then swap in the real device later.

---

## Project layout

```
heart-heat-sensor/
├── ios/          iOS app (Swift + SwiftUI + CoreBluetooth)
└── backend/      Sync API (Node.js + TypeScript + Fastify + SQLite)
```

---

## 1. Running the backend

### Prerequisites
- Node.js ≥ 20
- (Optional) Docker + Docker Compose

### Quick start (Node.js)

```bash
cd backend
npm install
cp .env.example .env          # edit JWT_SECRET at minimum
npm run dev                   # starts on http://localhost:3000
```

### Quick start (Docker)

```bash
cd backend
docker-compose up
```

### Seed the database with demo data

```bash
npm run seed
```

This creates a test account (`test@example.com` / `password123`) preloaded with 35 days of readings across four scenarios and fires the warnings engine:

| Days    | Scenario                                    | Warnings fired          |
|---------|---------------------------------------------|-------------------------|
| 1–28    | Normal week with workouts and sleep         | None                    |
| 29–31   | Getting sick — creeping HR + temp baseline  | `GETTING_SICK`          |
| 32–33   | Overheating workout — temp spike to 39.1 °C | `OVERHEATING`           |
| 34–35   | Poor recovery — elevated HR, low HRV        | `FATIGUE_RECOVERY`      |

### Running backend tests

```bash
npm test
# 50 tests, all in-process via Fastify inject() — no port required
```

### API overview

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/register` | — | Email + password registration |
| POST | `/auth/login` | — | Returns JWT |
| POST | `/auth/apple` | — | Sign in with Apple |
| POST | `/readings/batch` | JWT | Upload reading batch |
| GET  | `/readings` | JWT | Fetch history (`from`, `to`, `limit` params) |
| GET  | `/warnings` | JWT | Fetch user's warnings |
| GET  | `/warnings/:id` | JWT | Single warning detail |
| POST | `/warnings/recompute` | JWT | Re-run warnings engine |
| GET  | `/.well-known/apple-app-site-association` | — | Universal Links config |
| GET  | `/health` | — | Health check |

---

## 2. Running the iOS app

### Prerequisites

- macOS with **Xcode 15+** (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (install via `brew install xcodegen`)

### Generate the Xcode project

```bash
cd ios
bash generate_project.sh    # installs XcodeGen if missing, then generates HeartRate.xcodeproj
open HeartRate.xcodeproj
```

Select any iPhone 17 Simulator and press **⌘R** to run.

> **Team ID**: open `project.yml`, find `DEVELOPMENT_TEAM: ""` and set your Apple Developer Team ID if you want to run on a physical device.

### Running iOS unit tests

```bash
cd ios
xcodebuild test \
  -project HeartRate.xcodeproj \
  -scheme HeartRate \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | xcpretty
```

Tests cover:
- `HRMeasurementParserTests` — HR characteristic byte parsing (8-bit, 16-bit, RR intervals, energy expended, sensor contact)
- `TemperatureMeasurementParserTests` — IEEE-11073 float decoding, Fahrenheit conversion, site hints
- `WarningsEngineTests` — all three warning rules, baseline computation, RMSSD calculation

---

## 3. Demo Mode

Demo Mode feeds **simulated data through the same BLE pipeline** as a real device — the UI, parsers, and warnings engine see no difference.

### Enabling Demo Mode

- **First launch**: tap *"I don't have my device yet — use demo mode"* during onboarding pairing step
- **Any time**: Settings → Demo Mode toggle
- The mode persists in `UserDefaults` key `isDemoMode`

### Scenario presets

| Scenario | What it simulates |
|----------|-------------------|
| **Normal Week** | Typical HR 55–75 bpm, core 36.4–36.8 °C, circadian rhythm, workouts |
| **Overheating Workout** | Core temp spike to 39.1 °C during an active session → fires `OVERHEATING` |
| **Getting Sick (3 days)** | Resting HR creeps up +3 bpm/day, core temp +0.15 °C/day → fires `GETTING_SICK` |
| **Poor Recovery** | Elevated resting HR + very regular RR intervals (near-zero HRV) → fires `FATIGUE_RECOVERY` |

Switch scenarios in **Settings → Demo Scenario** or via the wand button on the Dashboard. Switching seeds fresh readings and immediately re-runs the warnings engine.

---

## 4. Deep links

### Custom URL scheme (`heartrate://`)

| URL | Navigates to |
|-----|-------------|
| `heartrate://dashboard` | Dashboard |
| `heartrate://history/hr` | HR history chart |
| `heartrate://history/core` | Core temp chart |
| `heartrate://history/hrv` | HRV chart |
| `heartrate://warnings/<uuid>` | Warning detail |
| `heartrate://settings` | Settings |
| `heartrate://pair` | Device pairing |

### Testing in Simulator

```bash
# Open a deep link in the booted Simulator
xcrun simctl openurl booted "heartrate://dashboard"
xcrun simctl openurl booted "heartrate://warnings/123e4567-e89b-12d3-a456-426614174000"
xcrun simctl openurl booted "heartrate://history/core"
```

### Universal Links

The backend serves `/.well-known/apple-app-site-association`. To enable Universal Links in production:

1. Deploy the backend to `yourdomain.com` over HTTPS.
2. Edit `ios/HeartRate/HeartRate.entitlements` — replace `yourdomain.com` with your actual domain.
3. Set `APPLE_TEAM_ID` env var on the backend so the AASA file contains your real team ID.
4. Universal Links then work as `https://yourdomain.com/warnings/<id>` etc.

---

## 5. Testing BLE with a simulated peripheral (LightBlue)

If you have an iPhone/iPad with [LightBlue](https://punchthrough.com/lightblue/), you can advertise a fake HR sensor:

1. Open LightBlue → **Create Virtual Device**
2. Add service `180D` (Heart Rate)
3. Add characteristic `2A37` (HR Measurement)
   - Value example (72 bpm, no RR): `0x00 0x48`
   - Value example (65 bpm, two RR intervals): `0x10 0x41 0xAA 0x03 0xB8 0x03`
4. Set it to notify
5. Run the iOS app in Simulator on the **same Mac** (BLE works between phone and Simulator via the Mac's Bluetooth adapter)

For temperature, add service `1809`, characteristic `2A1C`:
- Example (36.7 °C): `0x00 0x6F 0x01 0x00 0xFF`

---

## 6. Wiring the iOS app to the real device

When the nRF52840 DK is ready:

1. Turn off Demo Mode in Settings
2. The app scans for peripherals advertising `0x180D` (Heart Rate Service)
3. On connect, it discovers and subscribes to `0x2A37` (HR) and `0x2A1C` (Temperature)
4. A second temperature characteristic on the same service is automatically detected and labelled "Site 2"

The firmware only needs to implement standard GATT: HR Measurement notify + Temperature Measurement notify.

---

## Architecture notes

### iOS

```
BLE Layer ──► BLEService ──► Parsers ──► DataStore (SwiftData)
                                              │
                                              ▼
                                       WarningsEngine
                                              │
                                              ▼
                                     Views / Dashboard
```

- **BLETransportProtocol** makes `CoreBluetoothTransport` and `MockBLETransport` interchangeable
- **WarningsEngine** is a pure struct with static methods — fully unit testable, no SwiftData dependency
- **AppRouter** uses `NavigationPath` + typed `AppRoute` enum — every screen is deep-linkable
- **SwiftData** persistence, **Swift Charts** for all trend charts
- Sync is additive and optional — the app works 100% offline

### Backend

- **Fastify** + **better-sqlite3** — fast to start, single binary for local dev
- **JWT** authentication, bcrypt password hashing
- Warnings engine runs server-side as a recompute operation; client engine handles offline/realtime
- SQLite WAL mode for concurrent reads during sync

### Extension point — Garmin Health API

The `SyncService.swift` contains a clearly marked stub:

```swift
// MARK: - Future: Garmin Health API Integration
// func syncGarminData(token: String) async throws { fatalError("Not implemented") }
```

On the backend, add a `/integrations/garmin` route group when ready.

---

## Environment variables (backend)

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3000` | HTTP port |
| `JWT_SECRET` | `dev_secret_change_me` | **Change in production** |
| `DATABASE_PATH` | `./data/heartrate.db` | SQLite file path |
| `APPLE_CLIENT_ID` | `com.pulse.app` | Bundle ID checked against `aud` in Apple identity tokens |
| `APPLE_BUNDLE_ID` | `com.heartrate.app` | Bundle ID embedded in the AASA file |
| `APPLE_TEAM_ID` | `XXXXXXXXXX` | Apple Developer Team ID embedded in the AASA file |
| `API_BASE_URL` | `http://localhost:3000` | Set as Xcode env var to point the iOS app at staging |
