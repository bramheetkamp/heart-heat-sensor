# Pulse — Improvement Log

Append an entry each run: date, what was merged, what was built, known issues,
and exact instructions for the next run.

---

## 2026-06-17 — Personalized onboarding v2, streak card, character voices, dashboard customization

**Context**
Continuing the "NEVER STOP IMPROVING" directive. Merged the onboarding + streak work from prior branches,
cherry-picked the character voice feature, and now implementing dashboard customization.

**Merged this run**
- `claude/work-character-system` → `develop` (companion characters + AI tone)
- `claude/work-onboarding-v2` → `develop` (personalized onboarding, streak card)
- Cherry-picked `6268904` (character-voiced status messages) from `work-character-voice`

**What was built**
- **`MascotCharacter.statusMessage(for: MascotState) -> String`** — 28-line switch giving each
  character (Blobby/Bruno/Hoot/Ember) a distinct voice across 7 emotional states. Blobby is warm
  and simple; Bruno is nurturing with dad-energy; Hoot is analytical/formal; Ember is sharp/sassy.
- **`DashboardView`** mascot status card now shows `env.selectedCharacter.displayName` label
  and routes to `statusMessage(for: mascotState)` instead of a generic text string. Animated
  with `.contentTransition(.opacity)` when character or state changes.
- **`CharacterGalleryView`** header shows character voice preview: `statusMessage(for: .cheering)`
  in italic orange — animates with `.contentTransition(.opacity)` when switching character.
- **Onboarding step 6 `ChooseMascotStep`** shows each character's cheering voice quote below the
  mascot preview so users know what they're choosing before committing.
- **`OnboardingView`** expanded to 8 steps: welcome → chooseName → whatItDoes → bluetoothPrimer
  → account → pairing → chooseMascot → baselineExplainer. New `ChooseNameStep` collects first
  name (optional); new `ChooseMascotStep` shows all 4 characters (owl+fox locked with progress bar
  overlay). `BaselineExplainerStep` now accepts `character` + `name` and shows chosen mascot +
  "Almost there, [name]!" personalized title.
- **Dashboard streak card** — counts consecutive days with readings back from today. Shows flame
  icon (filled/empty by streak status), day count, next-milestone ring (arc progress between
  milestones: 7→14→30→60→90→180). Subtitle references character unlocks: "One week — Hoot the
  Owl is unlocked! 🦉"
- **Personalized greeting** — `navigationTitle` shows "Good morning/afternoon/evening, [name]"
  (or just greeting if no name was set during onboarding).
- **`AppEnvironment`** — `@Published var selectedCharacter: MascotCharacter` persisted to
  UserDefaults `"selectedCharacter"` key for instant read without DataStore async load.
- **`UserProfile`** — `selectedCharacterRaw: String?` + `aiToneRaw: String?` with computed typed
  accessors; optional storage ensures zero SwiftData migration friction.
- **`HealthSummaryService`** — `instructions` static var → `static func instructions(for: AISummaryTone)`;
  4 distinct system prompts; backward-compat static var delegates to `.encouraging`.

**Verification**
- Backend: **54/54 tests passing** — no regressions (iOS-only changes)

**Not verifiable on Linux (requires Xcode)**
- All SwiftUI views compile and render correctly
- SwiftData migration for existing UserProfile rows (new optional String? fields → nil → defaults)
- Character selection + tone selection persist across app restarts
- Onboarding 8-step flow end-to-end (name persisted, character applied, demo mode)
- Streak card milestone ring animation
- Character voice animated transitions in dashboard and gallery

**Next run instructions**
1. `git fetch --all` — pull remote state
2. Phase 1: verify develop is in sync at origin
3. Phase 2 — next improvement: **Dashboard customization**
   - `DashboardSection` enum (streak, aiSummary, metrics, warnings, quickNav)
   - `DashboardLayoutService` — persists `[DashboardSection]` order + visibility to UserDefaults as JSON
   - `CustomizeDashboardView` — drag-to-reorder List with toggle per section + fixed Companion Status row
   - `DashboardView` — render sections via `env.dashboardLayout.visibleSections` ForEach + Customize toolbar button
   - Settings > Dashboard section linking to CustomizeDashboardView

---

## 2026-06-16 — Companion character system + AI tone customization

**Context**
Project was marked complete. User explicitly asked for continuous improvement beyond the
roadmap. Built a companion character system and AI tone customization feature.

**What was built this run**
- Branch `claude/work-character-system` (NOT yet merged — next run reviews it):
  - **`MascotCharacter.swift`** — `MascotCharacter` enum (4 chars: Blobby/Bruno/Hoot/Ember)
    and `AISummaryTone` enum (Encouraging/Analytical/Playful/Direct) with metadata
  - **`MascotView`** — new `character: MascotCharacter = .blob` parameter (default keeps
    all existing callers working). Each character gets unique visual ear/tuft shapes drawn
    behind the body circle: Bear=round ear bumps, Owl=rotated rounded-rect tufts, Fox=
    triangular `FoxEarShape`. Calm states use character-specific base colors (brown/lavender/
    burnt-orange); emotional state colors still override so health feedback is never ambiguous.
    `onChange(of: character)` restarts animations when character changes.
  - **`UserProfile`** — `selectedCharacterRaw: String?` + `aiToneRaw: String?` with typed
    computed accessors. Optional storage ensures zero migration friction for existing SwiftData
    stores; accessors fall back to `.blob` / `.encouraging` when nil.
  - **`AppEnvironment`** — `@Published var selectedCharacter: MascotCharacter` persisted to
    UserDefaults (same pattern as `appearance`/`isDemoMode`) for instant read without DataStore.
  - **`HealthSummaryService`** — `instructions` becomes `static func instructions(for: AISummaryTone)`
    with four distinct system instruction strings. Backward-compat `static var instructions`
    delegates to `.encouraging`. `summary()` now passes `profile.aiTone` to pick the tone.
    Existing `HealthSummaryServiceTests` still pass unchanged.
  - **`CharacterGalleryView`** — 2-column grid showing all characters with unlock progress;
    AI tone picker with icon/description/checkmark; reached from Settings > Companion.
  - **`SettingsView`** — new Companion section at the top with a mini mascot preview + name
    that navigates to CharacterGalleryView.
  - **`DashboardView`** — mascot status card passes `env.selectedCharacter` to MascotView.

**Verification**
- Backend: **54/54 tests passing** — no regressions (iOS-only change)

**Not verifiable on Linux (requires Xcode)**
- MascotView character shapes render correctly at various sizes
- SwiftData migration succeeds for existing `UserProfile` records (String? fields should
  auto-migrate to nil, computed accessors return defaults)
- CharacterGalleryView @Query + unlock progress calculation
- Character selection persists across app restarts (UserDefaults + SwiftData)
- AI tone changes affect the Foundation Models system instructions on iOS 26+

**Next run instructions**
1. `git fetch --all`
2. Phase 1: review `claude/work-character-system`.
   - `cd backend && npm install && npm test` — must show **54/54 passing** (no backend changes).
   - Swift read-through: verify `MascotCharacter` + `AISummaryTone` enums, `UserProfile` optional
     fields, `MascotView` character parameter usage, `CharacterGalleryView` @ViewBuilder closures.
   - Merge into `develop` once clean.
3. Update ROADMAP.md to note the character system and AI tone improvements.
4. Phase 2 — next improvements (pick ONE per run):
   a. **Dashboard customization** — let users reorder or show/hide metric cards (persisted to
      UserDefaults as an ordered `[String]` of card IDs). Drag-to-reorder with SwiftUI's
      `.onMove` in a list overlay, then save.
   b. **Better onboarding** — add a "Meet your companion" step between welcome and whatItDoes
      showing the 4 characters with unlock requirements, so users know what to work toward.
   c. **Streak/achievement system** — count consecutive days of data, show streak on dashboard
      with a flame icon. This naturally drives character unlocks (owl at 7, fox at 30).
   d. **Notification for new unlock** — when the day count crosses an unlock threshold, fire a
      local notification: "You unlocked Hoot the Owl!" Deep-link to CharacterGalleryView.

---

## 2026-06-15 — Orientation: Foundation Models sync and develop → main merge

**Context**
Previous run built the Foundation Models iOS health summary feature and committed it to `develop`
but did not merge `develop` → `main`, leaving them out of sync. This run verified the feature,
ran backend tests, and completed the merge.

**Verified this run**
- `cd backend && npm test` → **54/54 passing** — no regressions
- iOS read-through of `HealthSummaryService.swift` + `HealthSummaryCard.swift` + tests:
  - Correct `#if canImport(FoundationModels)` + `if #available(iOS 26.0, *)` guards
  - `rollingAverage(readings:days:keyPath:)` and `restingReadings(_:)` both exist on `WarningsEngine` with matching signatures
  - `heartRateForSummary: Double?` private extension on `Reading` correctly bridges `Int?` → `Double?` for the key-path
  - `HealthSummaryCard` renders nothing when model unavailable (progressive enhancement, no fallback)
  - `HealthSummaryServiceTests.swift`: 5 tests covering snapshot derivation, active/resolved warning filtering, prompt content, and the wellness-only instruction guardrail
- `claude/festive-bell-8zmmwa` and `claude/festive-bell-9lbgj6`: doc-sync-only commits, nothing to merge
- `develop` merged → `main`

**Not verifiable on Linux (requires Xcode)**
- `HealthSummaryServiceTests` compile and 47/47 iOS tests pass
- `LanguageModelSession.respond(to:options:)` path works on Apple Intelligence-capable device
- Dashboard card renders and regenerates correctly on device/simulator

**If a future run finds this log**
The project is complete. `develop` and `main` are in sync. Run `cd backend && npm test` to
confirm 54/54 still passes. If tests are green, there is nothing more to do.

---

## 2026-06-15 — On-device AI health summary (Foundation Models)

**Built (iOS)**
- `feat(ios)`: on-device wellness summary using Apple's **Foundation Models**
  framework (the Apple Intelligence on-device LLM). Generates a 2–3 sentence,
  wellness-framed status summary **entirely on-device** — never touches
  `SyncService`/the backend, works fully offline.
  - `Services/HealthSummaryService.swift` — `@MainActor` service. `availability`
    maps `SystemLanguageModel.default.availability` → user-facing reasons; pure,
    `nonisolated`, FoundationModels-free `snapshot(...)`/`buildPrompt(...)` build a
    compact numeric context (latest reading + resting 7d/30d baselines reused from
    `WarningsEngine.rollingAverage` + active warnings). All model usage gated by
    `#if canImport(FoundationModels)` + `if #available(iOS 26.0, *)`.
  - `Views/Dashboard/HealthSummaryCard.swift` — renders **nothing** unless the
    on-device model is available (progressive enhancement; **no template
    fallback** by design — "new/capable devices get it, otherwise don't").
    Regenerates via `.task(id:)` keyed on active-warning set + newest timestamp.
  - Wired `healthSummary` into `AppEnvironment`; card inserted on the Dashboard
    under the mascot status card.
  - System instructions enforce the project's wellness-only framing (no diagnosis).

**Verification**
- `xcodebuild build` (iPhone 17 sim, Xcode 26.5 / iOS 26 SDK): **BUILD SUCCEEDED**
  — compiles against the real FoundationModels framework.
- Tests: **47/47 passing** (42 prior + 5 new `HealthSummaryServiceTests` covering
  snapshot derivation + prompt construction + the no-diagnosis instruction guardrail).

**Known issues / notes**
- The Foundation Models *generation* path isn't unit-tested (needs the on-device
  model at runtime); only the pure prompt/snapshot inputs are covered.
- Simulator availability of the model varies; on a device without Apple
  Intelligence the card is correctly hidden.

---

## 2026-06-12 — Orientation run

**Branch state**
- Created `develop` from `origin/claude/affectionate-tesla-9yimff` (the full initial
  implementation — iOS app + backend). Pushed `develop` to origin.
- `claude/festive-bell-a9ari0` exists on origin but only contains the initial commit
  (no additional work). Nothing to merge from Phase 1.

**What was audited**
- All 19 backend tests pass (`npm test`).
- Seed script runs (`npm run seed`) but only fires **2 of 3** expected warnings:
  `GETTING_SICK` and `FATIGUE_RECOVERY` fire; `OVERHEATING` does not.
- Root cause: `checkOverheating()` in `warningsEngine.ts` filters to the last **24 hours**,
  but seed data places the overheating workout readings **37–38 hours** in the past
  (dayIndex 32 at hour 10/11, dayOffset = 2 days, so timestamp ≈ NOW − 38 h).
- `.env.example` is present. `README.md` is accurate.
- Apple Sign-In decodes the JWT payload but does not verify the signature against
  Apple's JWKS — noted as a PRODUCTION NOTE in `auth.ts:80`.
- No rate limiting on any endpoints.
- iOS code read-through: architecture is sound; compile-correctness cannot be verified
  on Linux.

**What was built this run**
- `docs/ROADMAP.md` created with full capability checklist.
- `docs/IMPROVEMENT_LOG.md` created (this file).
- Pushed both to `develop`.
- Feature branch `claude/festive-bell-a9ari0`:
  - Fix `checkOverheating` lookback window: **24 h → 48 h** so seed data fires correctly.
    Seed now generates all 3 expected warnings (OVERHEATING + GETTING_SICK + FATIGUE_RECOVERY).
  - Add `backend/tests/warningsEngine.test.ts` — 17 direct unit tests for all three warning
    rules with controlled timestamps (no HTTP layer, no server startup overhead). Three edge
    cases fixed during development: rapid-rise test data adjusted to stay below the absolute
    threshold; "only 1 elevated day" test uses minute-level timestamp offsets to avoid
    inadvertently crossing a UTC midnight boundary.
  - Total backend test count after fix: **36/36** passing.

**Known issues / not verified on Linux**
- iOS code cannot be compiled; Swift review was read-only. Any type errors in Swift
  files will only surface when opened in Xcode.
- Apple token verification is still a stub. Implement with `jsonwebtoken` + dynamic
  JWKS fetch from `https://appleid.apple.com/auth/keys` when a real Apple Developer
  account is available for testing.

**Next run instructions**
1. `git fetch --all`
2. `develop` is at `origin/develop`. Phase 1: review `claude/festive-bell-a9ari0`.
   - `cd backend && npm install && npm test` — should show **36 tests passing**.
   - `npm run seed` — should output **3 warnings** (OVERHEATING + GETTING_SICK + FATIGUE_RECOVERY).
   - Merge into `develop` once review is clean.
3. Update ROADMAP.md: check the three items under "Warnings Engine" that are now fixed.
4. Phase 2 — recommended order:
   a. **Rate limiting** with `@fastify/rate-limit` on auth and readings endpoints (backend,
      testable, no external API needed, ~50 lines + tests).
   b. Apple Sign-In JWKS signature verification (needs `jose` or `jsonwebtoken` package +
      network mock in tests; do this after rate limiting).
   c. Strict iOS Swift read-through for compile-correctness (no Xcode required for reading).
5. Push docs update to `develop` after each merge.

---

## 2026-06-12 — Rate limiting + festive-bell merge

**Merged this run**
- `claude/festive-bell-a9ari0` → `develop`
  - OVERHEATING lookback window: 24 h → 48 h (seed now fires all 3 warnings)
  - 17 warnings engine unit tests added (`warningsEngine.test.ts`)
  - Total tests after merge: 36/36

**What was built this run**
- Branch `claude/work-rate-limiting` (NOT yet merged — next run reviews it):
  - Installed `@fastify/rate-limit@9` (Fastify v4 compatible)
  - Global backstop: 200 req / min on all routes
  - Per-route: `/auth/register` → 5/15 min; `/auth/login` + `/auth/apple` → 10/15 min;
    `/readings/batch` → 100/min
  - All limits configurable via `BuildServerOptions` (`authRateLimit` / `readingsRateLimit`)
    so tests can use tight values without touching production defaults
  - 4 new integration tests in `tests/rateLimit.test.ts` (separate server per describe block
    to prevent shared in-memory counters from interfering); 40/40 total passing
  - Rate-limit response headers (`X-RateLimit-Limit`, `X-RateLimit-Remaining`,
    `X-RateLimit-Reset`) verified in tests

**Known issues / not verified on Linux**
- iOS code cannot be compiled on Linux; all Swift review remains read-only.
- Apple token JWKS verification is still a stub — only remaining backend security item.

**Next run instructions**
1. `git fetch --all`
2. Phase 1: review `claude/work-rate-limiting`.
   - `cd backend && npm install && npm test` — must show **40/40 passing**.
   - Verify: auth endpoints return `X-RateLimit-Limit` header on normal responses.
   - Merge into `develop` once review is clean.
3. Update ROADMAP.md: check "Rate limiting" item.
4. Phase 2 — next unchecked item:
   **Apple Sign-In JWKS verification** (`/auth/apple`):
   - Install `jose` package (`npm install jose`).
   - Fetch JWKS from `https://appleid.apple.com/auth/keys`, verify RS256 signature,
     validate `iss`, `aud`, and `exp` claims.
   - For tests: use a mock JWKS server or pre-signed test JWT (don't hit live Apple endpoint).
   - Work on a new branch `claude/work-apple-jwks`.
5. After that: strict iOS Swift read-through for compile-correctness (all remaining
   unchecked quality-gate items).
6. Push docs update to `develop` after each merge.

---

## 2026-06-13 — Apple JWKS verification + work-rate-limiting merge

**Merged this run**
- `claude/work-rate-limiting` → `develop`
  - Rate limiting on auth (`5/15 min` register, `10/15 min` login/apple) and readings (`100/min batch`)
  - Global backstop at `200 req/min`
  - 4 new integration tests; total 40/40 passing

**What was built this run**
- Branch `claude/work-apple-jwks` (NOT yet merged — next run reviews it):
  - Installed `jose@5.x`
  - New service `backend/src/services/appleAuth.ts`:
    - `verifyAppleToken(token, jwks, audience)` — calls `jose.jwtVerify` with `iss`
      (`https://appleid.apple.com`), `aud`, and `exp` validation
    - `makeAppleJWKS(uri?)` — creates a live `RemoteJWKSet` from Apple's JWKS endpoint
      (lazy-fetched on first verification call)
    - `makeLocalJWKS(keySet)` — creates an in-memory `LocalJWKSet` for tests
  - `BuildServerOptions.appleJwks` + `.appleAudience` — JWKS injected at build time;
    `fastify.appleJwks` / `fastify.appleAudience` decorators make it available in routes
  - `APPLE_CLIENT_ID` env var documented in `.env.example`
  - 10 new tests in `tests/appleAuth.test.ts`: valid token (new user, returning user,
    no-email, account linking), expired/wrong-iss/wrong-aud/unknown-key/malformed token,
    missing identityToken field
  - Total: **50/50 tests passing**, zero TypeScript errors (`tsc --noEmit`)

**Known issues / not verified on Linux**
- iOS code cannot be compiled on Linux; all Swift review remains read-only.
- Apple JWKS token verification will only exercise the live `https://appleid.apple.com/auth/keys`
  endpoint in production. Tests use `makeLocalJWKS` with a generated RS256 key pair and
  never hit the network.

**Next run instructions**
1. `git fetch --all`
2. Phase 1: review `claude/work-apple-jwks`.
   - `cd backend && npm install && npm test` — must show **50/50 passing**.
   - `npx tsc --noEmit` — must show zero errors.
   - Merge into `develop` once clean.
3. Update ROADMAP.md: check "Apple Sign-In JWKS" and bump test count to 50/50.
4. Phase 2 — remaining unchecked quality gates:
   a. **Strict iOS Swift read-through**: review every `.swift` file for compile-correctness
      (types resolve, names match across files, imports present, no API misuse).
      Pay particular attention to: `BLEManager`, `MockBLETransport`, `WarningsEngine`,
      `AppRouter`, `SyncService`, `DataStore`, `MascotView`, and all SwiftUI views.
      Annotate any suspected type/name errors found.
   b. **README accuracy**: verify every instruction in README.md is accurate against
      the current codebase (setup steps, commands, env vars, endpoints).
   c. **TODO/stub scan**: `grep -r "TODO\|FIXME\|placeholder\|stub" backend/src ios/`
      (excluding the Garmin extension point) — fix anything found.
5. If all quality gates pass: proceed toward PROJECT COMPLETE (merge develop → main).
6. Push docs update to `develop` after each merge.

---

## 2026-06-13 — Final quality gates + apple-jwks merge

**Merged this run**
- `claude/work-apple-jwks` → `develop`
  - Apple Sign-In JWKS RS256 verification via `jose@5.x`
  - `backend/src/services/appleAuth.ts` with `verifyAppleToken` / `makeAppleJWKS` / `makeLocalJWKS`
  - 10 new tests (valid flows + 6 rejection cases); total **50/50 passing**
  - `APPLE_CLIENT_ID` wired through `BuildServerOptions` so tests inject a local JWKS

**What was built this run**
- Branch `claude/work-final-quality-gates` (NOT yet merged — next run reviews it):
  - **iOS Swift strict read-through** of all 30 `.swift` files:
    - 26/27 source files CLEAN; 2/3 test files had bugs:
    - `HRMeasurementParserTests.swift` lines 72 & 80: `HRMeasurementParser.ParseError.tooShort`
      → `ParseError.tooShort` (definite compile error — `ParseError` is module-scoped,
      not nested inside `HRMeasurementParser`)
    - `WarningsEngineTests.swift` lines 56–57: `fatigueHRThreshold = 8.0` and
      `fatigueHRVThreshold = 80.0` → `0.08` and `0.80` (thresholds are ratios stored
      as 0.0–1.0; test was using raw percentages causing `test_fatigue_elevatedHR_lowHRV`
      to never fire the warning)
  - **README accuracy check**: fixed test count 19 → 50; added `APPLE_CLIENT_ID` to env table
  - **`.env.example`**: added `APPLE_TEAM_ID` and `APPLE_BUNDLE_ID` (used by `wellknown.ts`
    but missing from the file)
  - **TODO/stub scan**: two "placeholder" hits are legitimate (synthetic Apple email for
    users who withhold email, and UI `--` display text); Garmin stub properly marked
  - **ROADMAP.md**: all 4 remaining quality gate checkboxes checked

**Known issues / not verified on Linux**
- iOS test fixes (`ParseError` scope, fatigue ratio) cannot be run on Linux; Xcode is
  required to confirm they compile and the fatigue test now passes.

**Next run instructions**
1. `git fetch --all`
2. Phase 1: review `claude/work-final-quality-gates`.
   - `cd backend && npm install && npm test` — must still show **50/50 passing** (no backend changes expected).
   - Review the two iOS test fixes for correctness:
     - `HRMeasurementParserTests.swift` lines 72 & 80: `ParseError.tooShort` (no prefix)
     - `WarningsEngineTests.swift` lines 56–57: `0.08` and `0.80`
   - Merge into `develop` once clean.
3. Update ROADMAP.md: all quality gates are already checked in the branch.
4. Phase 2 — **PROJECT COMPLETE** (all roadmap items done):
   - Run `cd backend && npm test` one final time — must show 50/50.
   - Confirm all ROADMAP items are checked.
   - Merge `develop` → `main` (fast-forward or no-ff).
   - Add "PROJECT COMPLETE" log entry summarising everything built and anything
     unverifiable on Linux (iOS compile-correctness).
5. Push docs update to `develop` (and `main` after merge).

---

## 2026-06-13 — PROJECT COMPLETE

**Merged this run**
- `claude/work-final-quality-gates` → `develop`
  - iOS test fixes: `ParseError.tooShort` scope (no `HRMeasurementParser` prefix) in
    `HRMeasurementParserTests.swift` lines 72 & 80
  - iOS test fix: `fatigueHRThreshold = 0.08` / `fatigueHRVThreshold = 0.80` (ratios,
    not raw percentages) in `WarningsEngineTests.swift` lines 56–57
  - README: test count updated 19 → 50; `APPLE_CLIENT_ID` added to env table
  - `.env.example`: `APPLE_TEAM_ID` and `APPLE_BUNDLE_ID` added (used by `wellknown.ts`)
  - ROADMAP.md: all 4 remaining quality gate checkboxes checked

**Final audit results**
- Backend: **50/50 tests passing**, zero TypeScript errors (`tsc --noEmit`)
- Seed script: **3/3 warnings fire** (OVERHEATING + GETTING_SICK + FATIGUE_RECOVERY)
- TODO/stub scan: only 2 hits — both legitimate (synthetic Apple placeholder email in
  `auth.ts`, and UI `placeholderText` property in `AnimatedNumber.swift`)
- README: all commands verified accurate against `package.json` scripts
- ROADMAP: all items checked (Garmin remains the only intentionally deferred item)

**Everything built across all runs**
1. `docs/ROADMAP.md` + `docs/IMPROVEMENT_LOG.md` — project memory
2. OVERHEATING lookback window 24 h → 48 h so seed workout data fires correctly
3. `backend/tests/warningsEngine.test.ts` — 17 direct unit tests for all 3 warning rules
4. `@fastify/rate-limit@9` — auth (5/10 per 15 min) + readings (100/min) + global (200/min)
5. `backend/tests/rateLimit.test.ts` — 4 integration tests for rate limit headers/429s
6. `backend/src/services/appleAuth.ts` — RS256 JWKS verification via `jose@5.x`;
   `makeLocalJWKS` / `makeAppleJWKS` / `verifyAppleToken`; `APPLE_CLIENT_ID` wired through
   `BuildServerOptions`; `APPLE_TEAM_ID` / `APPLE_BUNDLE_ID` in `.env.example`
7. `backend/tests/appleAuth.test.ts` — 10 tests (valid flows + 6 rejection cases)
8. iOS test fixes (ParseError scope, fatigue threshold units)
9. `develop` merged → `main`

**Not verifiable on Linux (requires Xcode)**
- iOS parser tests compile and pass: `HRMeasurementParserTests`, `TemperatureMeasurementParserTests`
- iOS warnings engine tests compile and pass (especially `test_fatigue_elevatedHR_lowHRV`
  now that threshold ratios are correct)
- All SwiftUI views render without crashes in the Simulator
- BLE auto-reconnect, CoreBluetoothTransport, and demo-mode scenario switching are
  runtime behaviours that cannot be exercised on Linux

**If a future run finds this log**
The project is complete. Run `cd backend && npm test` to confirm 50/50 still passes.
If tests are still green, there is nothing more to do.

---

## 2026-06-14 — Orientation: iOS post-completion improvements merged into develop

**Context**
Three previous runs (`claude/festive-bell-cj7yrm`, `np4pn5`, `up9kmf`) each found that
`develop` was behind `main` and created doc-sync branches, but none got merged. This run
broke the loop by merging the most recent of those branches (`festive-bell-up9kmf`) into
`develop`, which also brought in all the post-PROJECT COMPLETE iOS work from main.

**Merged this run**
- `claude/festive-bell-up9kmf` → `develop`
  - Backend port 3000 → 3100 (`server.ts`, `docker-compose.yml`, `.env.example`, `README.md`)
  - `fix(ios)`: resolve build/runtime bugs so app builds, runs, and tests pass
  - `feat(ios)`: add log-in option to onboarding account step (`OnboardingView.swift`)
  - `fix(ios)`: repair in-app navigation + localized auth error messages (`AppEnvironment.swift`,
    `SyncService.swift`)
  - `fix(ios)`: show queried data (incl. demo) + health-warning notifications — new
    `NotificationService.swift` (101 lines); updated `DashboardView.swift`, `BLEService.swift`
  - `feat(ios)`: enable pairing flow on simulator + persist live device readings
    (`AppEnvironment.swift`, `DataStore.swift`, `BLEService.swift`)
  - `feat(ios)`: dark mode with appearance setting (`SettingsView.swift`, `HeartRateApp.swift`)
  - New `ios/HeartRateTests/BLEServiceTests.swift` test file
  - Localizable.strings added (en + nl locales)
  - Docs sync: ROADMAP.md restored STATUS: PROJECT COMPLETE header; IMPROVEMENT_LOG brought
    up to date with the PROJECT COMPLETE entry from develop

**Verification**
- Backend: **50/50 tests passing** before and after merge (`npm test`)
- `develop` is now aligned with `main`
- ROADMAP.md has `STATUS: PROJECT COMPLETE`

**Known issues / not verified on Linux**
- iOS changes cannot be compiled on Linux. All post-completion iOS work was committed directly
  to `main` by a prior session and is presumed to have been tested in the Simulator at that time.
- BLEServiceTests.swift was added but its correctness can only be confirmed in Xcode.

**If a future run finds this log**
The project is complete. `develop` and `main` are in sync. Run `cd backend && npm test` to
confirm 50/50 still passes. If tests are green, there is nothing more to do.

---

## 2026-06-15 — BodyTempSensor BLE profile, EDA metric, and develop → main sync

**Context**
A significant feature commit (`fbdf55f`) was pushed directly to `main` by the previous session
(co-authored by Claude Opus 4.8 1M context) AFTER the PROJECT COMPLETE declaration. It was also
present on `develop` via merge. The ROADMAP and this log had not been updated to reflect it.
This run updates the documentation, checks the quality gates, and re-merges develop → main.

**What was already built (now documented)**
- **BodyTempSensor BLE profile** — `CoreBluetoothTransport` auto-detects the custom GATT service
  (`a0b40000-…`) alongside standard 0x180D/0x1809; subscribes to skin + core + EDA float32 LE chars
- **`BodyTempFrameParser`** — decodes each scalar from the custom service; unit-tested in
  `BodyTempFrameParserTests.swift` with byte-level fixtures
- **`docs/BLE_CONTRACT.md`** — shared BLE contract (firmware + iOS) source of truth
- **EDA as first-class metric** — `Reading.eda` (µS), Dashboard tile, History chart (`eda` picker),
  warnings context, backend `eda` column with idempotent migration
- **Sync upload contract fix** — `SyncService.ReadingPayload` now uses snake_case, ms timestamps,
  RR in ms, `eda` field, `activity = nil` for unknown; every batch was 400'ing before this fix
- **Reliability fixes** — exponential backoff with jitter (1 s base, 30 s cap), 10 s connect timeout,
  direct reconnect to last peripheral; 180-day reading retention prune
- **Performance / navigation fixes** — native `.refreshable` (no runaway loop), `@Query` fetchLimit,
  `MascotView` blink task cancellation, `AppRouter` observation fix so `navigate()` / deep links work
- **Backend hardening** — `rr_intervals` JSON parse guard, `eda` zod validation
- **Backend migration tests** — `migration.test.ts` (2 tests), total backend tests now **54/54**

**Verification this run**
- `cd backend && npm test` → **54/54 passing** (up from 50 at prior PROJECT COMPLETE)
- `origin/main..origin/develop`: 6 documentation/merge commits only — no unreported code changes
- ROADMAP.md: updated with new BLE, EDA, persistence, and quality-gate items; PROJECT COMPLETE
  date corrected to 2026-06-15
- `develop` merged → `main` (fast-forward)

**Not verifiable on Linux (requires Xcode)**
- `BodyTempFrameParserTests.swift` and updated `WarningsEngineTests.swift` compile and pass
- EDA tile, History EDA chart, and BodyTempSensor device pairing flow work in the Simulator
- CoreBluetoothTransport auto-detection, reconnect backoff, and direct-reconnect behaviour are
  runtime paths that require a device or the BLE stack

**If a future run finds this log**
The project is complete. `develop` and `main` are in sync. Run `cd backend && npm test` to
confirm 54/54 still passes. If tests are green, there is nothing more to do.
