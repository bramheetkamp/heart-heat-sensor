# Pulse — Improvement Log

Append an entry each run: date, what was merged, what was built, known issues,
and exact instructions for the next run.

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
