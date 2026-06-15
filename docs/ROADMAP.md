# Pulse — Development Roadmap

**STATUS: PROJECT COMPLETE (2026-06-15)** — all items checked; `develop` merged → `main`.

Derived from the product spec and codebase audit. Each item must be complete
(no placeholders, no stubs) before being checked. Garmin integration is the
only intentionally deferred item.

---

## BLE & Parsing

- [x] `BLETransportProtocol` — mock and real transport interchangeable
- [x] `CoreBluetoothTransport` — production CoreBluetooth with scan / connect / notify
- [x] `MockBLETransport` — scenario-driven simulation through the same protocol
- [x] Auto-reconnect with exponential backoff + jitter, 10 s connect timeout, direct reconnect to last peripheral
- [x] HR characteristic 0x2A37 — 8-bit and 16-bit value parsing
- [x] HR characteristic 0x2A37 — RR interval extraction (1/1024 s units)
- [x] Temperature characteristic 0x2A1C — IEEE-11073 32-bit float decoding
- [x] Two named temperature streams (site1 / site2)
- [x] Parser unit tests with byte-level fixtures (`HRMeasurementParserTests`, `TemperatureMeasurementParserTests`)
- [x] **BodyTempSensor custom GATT profile** — auto-detected alongside standard GATT; skin + core + EDA float32 LE chars
- [x] `BodyTempFrameParser` — decodes float32 LE scalars from custom service chars
- [x] `BodyTempFrameParserTests` — unit tests with byte fixtures
- [x] `docs/BLE_CONTRACT.md` — shared BLE contract used by firmware and iOS app
- [x] Persist temperature/EDA-only readings (no HR) for BodyTempSensor device

---

## Warnings Engine

- [x] OVERHEATING rule — absolute threshold (38.5 °C) + fast rise (≥1 °C in 30 min during activity)
- [x] GETTING_SICK rule — resting HR / temp elevated vs 30-day rolling baseline for ≥2 consecutive days
- [x] FATIGUE_RECOVERY rule — elevated resting HR + suppressed HRV (RMSSD from RR intervals) for ≥2 consecutive days
- [x] Every warning includes trigger values, baseline values, and a trend array (shows WHY)
- [x] Wellness framing only — no medical diagnosis language
- [x] iOS `WarningsEngineTests` — all three rules, baseline computation, RMSSD edge cases
- [x] **Fix OVERHEATING engine window: 24 h → 48 h so seed workout data fires correctly**
- [x] Backend warnings engine unit tests (direct function calls with controlled timestamps, all 3 rules, 17 tests)
- [x] Seed script fires all 3 expected warnings (OVERHEATING + GETTING_SICK + FATIGUE_RECOVERY)

---

## iOS App — Views & UX

- [x] Dashboard — at-a-glance status, 2×2 metric grid, top warnings, demo scenario picker
- [x] History — Swift Charts line + area, metric picker (HR / core / skin / HRV), time range (24 h / 7 d / 30 d), stats and baseline card
- [x] Warnings list — active + resolved sections, "all clear" mascot state
- [x] Warning detail — WHY card with trigger/baseline numbers, trend chart, suggestions, medical disclaimer
- [x] Multi-step onboarding (6 steps) with demo-mode fallback path
- [x] Settings — demo toggle, scenario picker, threshold sliders, account sync, device scan
- [x] `MascotView` — 8 emotional states, per-state animations (bounce, wiggle, blink, sweat drops, z-floats, sparkles, pulse, scan rings)
- [x] `AnimatedNumber` — spring-animated value updates with unit display
- [x] `ConnectionStatusBadge` — state-based colour + pulsing indicator
- [x] Haptics and micro-interactions throughout

---

## Navigation & Deep Links

- [x] `NavigationStack` + typed `AppRoute` enum — every screen addressable
- [x] `heartrate://` custom URL scheme with routes for all screens
- [x] Universal Links — backend serves `/.well-known/apple-app-site-association`
- [x] `AppRouter` — NavigationPath state management, URL parsing, sheet presentation

---

## Demo Mode

- [x] Simulated BLE streams flow through the same pipeline as real hardware
- [x] Normal Week scenario — circadian HR + temp, sleep + workout windows
- [x] Overheating Workout scenario — temp spike to 39.1 °C → fires OVERHEATING
- [x] Getting Sick scenario — progressive HR + temp rise → fires GETTING_SICK
- [x] Poor Recovery scenario — elevated resting HR + suppressed HRV → fires FATIGUE_RECOVERY
- [x] Scenario switching in Settings and Dashboard toolbar

---

## EDA Metric

- [x] `Reading.eda` field — persisted in SwiftData and synced to backend
- [x] EDA tile on Dashboard — live value display
- [x] EDA history chart — line/area chart in History view with metric picker
- [x] EDA in warnings context — surfaced in `WarningsEngine` trigger values
- [x] Backend `eda` column with idempotent `migrate()` (never drops existing tables)
- [x] Backend migration tests (`migration.test.ts`, 2 tests)
- [x] Sync upload contract fixed — snake_case keys, ms timestamps, RR in ms, `eda` field, `activity` nil for unknown

---

## Persistence & Sync

- [x] SwiftData persistence for `Reading` and `HealthWarning` models
- [x] `DataStore` — save / fetch / mark-synced helpers
- [x] `SyncService` — register, login, batch upload, warnings fetch; upload contract matches backend zod schema
- [x] Garmin Health API extension point — clearly marked commented stub (intentionally unimplemented)
- [x] Bounded 180-day reading retention prune (on-device storage bound)

---

## Backend

- [x] Fastify + better-sqlite3 — single-command local run (`npm run dev`)
- [x] Schema: users, readings, warnings tables with indexes and WAL mode
- [x] `POST /auth/register` — email + bcrypt password
- [x] `POST /auth/login` — credential validation + JWT
- [x] `POST /auth/apple` — Sign in with Apple with full RS256 JWKS verification (`iss`, `aud`, `exp`)
- [x] `POST /readings/batch` — upsert up to 1 000 readings per call
- [x] `GET /readings` — history with `from` / `to` / `limit` filters
- [x] `GET /warnings`, `GET /warnings/:id` — list and detail
- [x] `POST /warnings/recompute` — server-side re-run of warnings engine
- [x] `GET /.well-known/apple-app-site-association` — Universal Links config
- [x] `GET /health` — health check
- [x] `.env.example` present with all required variables documented
- [x] Seed script — 35 days of scenario data, test account `test@example.com / password123`
- [x] 19 API integration tests, all passing (`npm test`)
- [x] **Apple Sign-In: verify `identityToken` signature against Apple's JWKS endpoint (production security)**
- [x] Rate limiting on auth and readings endpoints (brute-force / abuse protection)

---

## Quality Gates (must all pass before PROJECT COMPLETE)

- [x] Backend tests passing (`npm test` → 54/54 after BodyTempSensor + EDA + migration work)
- [x] Seed script fires all 3 expected warnings (verified)
- [x] All ROADMAP items above checked (except Garmin)
- [x] No remaining TODOs / placeholder stubs in source (except marked Garmin stub)
- [x] README instructions verified accurate
- [x] iOS Swift files pass strict manual review (types resolve, names match, imports present, no API misuse)
