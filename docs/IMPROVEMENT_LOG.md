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
- Feature work started on `claude/festive-bell-a9ari0`:
  - Fix `checkOverheating` lookback window: **24 h → 48 h** so seed data fires correctly.
  - Add `backend/tests/warningsEngine.test.ts` — direct unit tests for all three warning
    rules with controlled timestamps (no HTTP layer, no server startup overhead).

**Known issues / not verified on Linux**
- iOS code cannot be compiled; Swift review was read-only. Any type errors in Swift
  files will only surface when opened in Xcode.
- Apple token verification is still a stub. Implement with `jsonwebtoken` + dynamic
  JWKS fetch from `https://appleid.apple.com/auth/keys` when a real Apple Developer
  account is available for testing.

**Next run instructions**
1. `git fetch --all`
2. Develop is at `origin/develop`. Phase 1: review `claude/festive-bell-a9ari0` —
   it should contain the OVERHEATING fix + new `warningsEngine.test.ts`. Run
   `cd backend && npm install && npm test` (should now be ≥ 19 + new engine tests).
   Run `npm run seed` and confirm all **3** warnings fire.
3. Merge `claude/festive-bell-a9ari0` into `develop` once tests are green.
4. Phase 2: pick the next unchecked ROADMAP item. Recommended order:
   a. Apple Sign-In JWKS signature verification (backend, testable).
   b. Rate limiting with `@fastify/rate-limit` + tests.
   c. Strict iOS Swift review pass (compile-correctness, no Xcode needed for reading).
5. Push docs update to `develop` after merge.
