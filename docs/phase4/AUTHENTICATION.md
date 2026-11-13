# Phase 4 authentication

The catalog and pricing routes remain public. Auth code is isolated in backend/src/modules/auth and lib/features/auth. There is no registration, JWT, order processing or operational dashboard.

## Local setup

From backend/, configure the existing private .env database URLs, NODE_ENV=development and DEMO_AUTH_ENABLED=true. Run `npm run db:migrate`, `npm run auth:bootstrap`, `npm run db:seed:auth`, `npm run build`, then `npm start`. Bootstrap generates missing passwords only into ignored .env; it never prints them. Read the corresponding DEMO_CUSTOMER_PASSWORD, DEMO_RESTAURANT_PASSWORD, DEMO_RIDER_PASSWORD or DEMO_ADMIN_PASSWORD locally when signing in. Do not commit that file. Existing seeded passwords and memberships are never overwritten by repeat seeding; editing an env password does not reset an existing account.

Accounts: customer@demo.test, restaurant@demo.test, rider@demo.test, admin@demo.test. The owner has one membership, deccan-handi-gachi. Debug Flutter builds offer email shortcuts only. Production rejects DEMO_AUTH_ENABLED=true, cannot seed demo users, and rejects existing demo sessions/logins when the flag is disabled.

For an explicitly requested local credential change, update the private DEMO_*_PASSWORD values and run `npx tsx scripts/reset-demo-passwords.ts`. This development-only command updates only the four existing demo users, verifies their hashes and revokes existing sessions. Local demo passwords allow 8–128 characters; bootstrap still generates random credentials by default.

## API contract

All paths start /api/v1. Existing data/error envelopes apply.

| Method/path | Behavior |
| --- | --- |
| POST auth/login | Validated email/password; returns public user and opaque Bearer session with expiry |
| GET auth/me | Current user, active memberships and session expiry |
| PATCH auth/me | Only trimmed displayName, 2–80 characters |
| POST auth/logout | Revoke current session |
| POST auth/logout-all | Revoke all sessions of the current user |
| GET account/restaurant/:id | RESTAURANT_OWNER plus active OWNER membership for that exact restaurant |
| GET account/delivery | DELIVERY_PARTNER context for the current user |
| GET account/admin | Explicit ADMIN context |

401 means missing/invalid/expired/revoked session (login uses a generic credentials error). 403 means no role or membership. 429 means throttled login. Unknown DTO fields are rejected, including role/user-id escalation. No implicit admin bypass is applied to owner/delivery endpoints. Authorization reads current roles/status on each request. Auth responses/errors have Cache-Control: no-store. Request logs include only request ID, method, status and timing.

Passwords use Argon2id, 64 MiB memory, 3 iterations, parallelism 1 and independent salts. Tokens are 32 cryptographically random bytes encoded base64url; only SHA-256 token hashes persist in PostgreSQL. Default lifetime is 12 hours (AUTH_SESSION_HOURS allows 1–168). Logout-all and login serialize using the user row lock. Expired/revoked records are retained; production retention cleanup is a future operational task.

The in-process limiter permits 30 attempts/IP and 10/normalized email per ten minutes, with bounded memory and no trust of forwarded headers. This is suitable for the local single-process phase. Multi-instance deployment requires a shared limiter and explicit proxy trust policy. Limits include successful attempts.

Flutter uses native secure storage for the token only; SharedPreferences contains no session credentials. A separate authenticated Dio client attaches tokens only to its configured origin and refuses redirects. 401 clears the matching session; an older failed request cannot clear a newer token. Public discovery uses the existing public client. Failed remote logout retains the session for retry, while expiry clears local state. Android backup is disabled to prevent credential restoration outside its encryption keys. Use HTTPS outside local debug development.

## Verification

`npm run test:auth` targets only food_delivery_test and refuses other database names. `npm run test:e2e` also includes catalog and pricing regression tests. No test resets food_delivery_dev.

For Android, start the API on port 5001, run `npx tsx scripts/auth-test-defines.ts` from backend/ and use the ignored build/auth-test-defines.json with `flutter drive --driver=test_driver/authentication.dart --target=integration_test/authentication_test.dart -d emulator-5554 --dart-define-from-file=build/auth-test-defines.json`. The integration-test APK contains local test credentials: never distribute it. Production builds must target lib/main.dart without that define file. Native encrypted persistence is verified across complete Flutter provider/router disposal and reconstruction; this is distinct from an OS process-death test.
