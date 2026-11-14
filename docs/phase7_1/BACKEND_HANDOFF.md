# Phase 7.1A backend handoff

Date: 2026-11-13. Branch: `feature/f7-secure-handover`. Backend only; no commit, push or merge. This document supersedes Phase 7's direct `deliver` contract. Google Antigravity should integrate Flutter against these routes, not recreate this backend.

## Files

Added:
- `backend/src/modules/operations/handover.crypto.ts`
- `backend/src/modules/operations/handover.service.ts`
- `backend/src/modules/operations/handover.controller.ts`
- `backend/prisma/migrations/202611130003_secure_handover/migration.sql`
- `backend/scripts/setup-handover-keys.ts`
- `backend/test/handover-checks.ts`
- `docs/phase7_1/BACKEND_HANDOFF.md`
- `docs/phase7_1/IMPLEMENTATION_STATUS.md`

Modified:
- `backend/prisma/schema.prisma`
- `backend/src/modules/operations/operations.module.ts`
- `backend/src/modules/operations/operations.service.ts`
- `backend/test/commerce.e2e.test.ts`
- `backend/test/operations-checks.ts`
- `backend/test/unit.test.ts`
- `backend/.env.example`

Existing dirty README, Phase 7 implementation status and two Flutter integration tests were preserved. No Flutter files were changed by this task. Private `.env` gained locally generated handover keys; it remains ignored.

## Migration and preservation

`202611130003_secure_handover` adds DeliveryHandover and HandoverAudit. Applied to `food_delivery_dev` and isolated `food_delivery_test`; seven migrations, development schema up to date. No old migration was edited, no database reset, no seed run. Existing trigram and active-rider indexes are preserved.

One mutable challenge row per order (unique orderId) prevents multiple active challenges. Regeneration replaces its verifier/binding and appends an audit entry with the previous challenge version. Attempt/issue/expiry/consumption CHECK constraints, assignment/order FKs, and order-level locking enforce consistency. Historical audit entries contain no PIN, verifier or encrypted payload. Previous challenge ciphertext is not retained.

Before/after SHA-256 comparisons of sorted complete rows matched for Orders (6), OrderItems (8), OrderItemAddOns (2), OrderEvents (14), DeliveryAssignments (1), PaymentAttempts (1), Restaurants (28), MenuItems (224), Localities (10). Historical delivered orders and captured Razorpay payment were untouched.

## Configuration

Required server-only settings: `HANDOVER_HMAC_KEY` and `HANDOVER_ENCRYPTION_KEY`, each independently generated 32-byte random value encoded as 64 hexadecimal characters. Equal, malformed or missing keys fail closed with 503. Never place these in Flutter, API configuration responses, source control or logs.

For local development, from `backend`, with `NODE_ENV=development` in the existing private `.env`, run `npx tsx scripts/setup-handover-keys.ts`. It uses crypto.randomBytes, appends only missing keys directly to private `.env`, never prints values, and never replaces an existing setting. Blank existing keys require deliberate repair; the script intentionally does not overwrite them. On Windows ensure the private file inherits restricted user ACLs. For deployments provision independently generated values through the server's secret manager. Restart the backend after configuration changes.

Optional: `HANDOVER_KEY_VERSION=v1`, `HANDOVER_TTL_SECONDS=600` (60–900), `HANDOVER_REGENERATE_SECONDS=60` (30–600). Invalid values fail closed. Fixed initial limits: five wrong attempts per challenge, three total issues per order, five-minute lock cooldown. Settings are read per request; use consistent keys across processes.

Coordinate key rotation during a handover maintenance window. This implementation supports one key version, not a key ring. Existing challenges cannot be redisplayed/verified after keys change. Customers may regenerate after their cooldown if their issue quota remains; exhausted cases require support investigation. Do not silently rotate keys on restart or erase challenge/attempt rows to bypass limits.

PIN generation uses Node crypto.randomInt(0,1000000), zero padded to six characters. Verification uses domain-separated HMAC-SHA256 and timingSafeEqual; redisplay uses separately keyed AES-256-GCM with a fresh random 12-byte nonce. Both authenticate orderId, assignmentId, boundRiderId, challengeVersion, issuedAt, expiresAt and keyVersion. See [Node crypto documentation](https://nodejs.org/api/crypto.html).

## HTTP contracts

All routes use existing `Authorization: Bearer <opaque session>` authentication and existing no-store responses. Responses have the existing `{data: ...}` envelope; errors use `{error: {code, message}, requestId}`. Dates are ISO UTC strings. Do not log request bodies or response PINs.

### Customer

`GET /api/v1/orders/:id/handover`: CUSTOMER role plus ownership, read only. Never generates/rotates a PIN. Another customer's order returns 404; owner/admin without customer role return 403. A rider with CUSTOMER role still needs actual order ownership. Roles do not override ownership.

`POST /api/v1/orders/:id/handover/issue`, body `{}`, returns 200. Explicit customer action only; requires order and current assignment OUT_FOR_DELIVERY, active assigned rider with delivery role, available quota and elapsed cooldown. Unknown properties including customerId or client PIN are rejected. First request issues; subsequent eligible requests regenerate and invalidate the previous challenge. This POST is not an idempotent redisplay operation: after a lost response, GET first.

Customer data example (illustrative PIN only):

```json
{
  "orderId": "<uuid>", "orderVersion": 7, "state": "ACTIVE",
  "challengeVersion": 1, "issuedAt": "<ISO UTC>", "expiresAt": "<ISO UTC>",
  "nextIssueAt": "<ISO UTC>", "attemptsRemaining": 5, "issuesRemaining": 2,
  "canIssue": false, "pin": "012345", "consumedAt": null
}
```

States: NOT_ISSUED, ACTIVE, EXPIRED, LOCKED, INVALIDATED, CONSUMED, UNAVAILABLE. PIN exists only in ACTIVE customer responses. Unissued timestamps/challengeVersion are null. `canIssue` reports state/quota/cooldown eligibility; POST also revalidates the rider. GET detects changed assignment as INVALIDATED without a write; the next mutation persists invalidation. Expired/locked ciphertext is never exposed; consumption and assignment invalidation erase ciphertext. Regeneration replaces it.

### Assigned rider

`POST /api/v1/operations/delivery/orders/:id/complete-handover`, body:

```json
{"pin":"012345","expectedVersion":7}
```

PIN must be a six-character numeric string, never an integer. No riderId accepted. Requires current DELIVERY_PARTNER role/session, ACTIVE account, actual assignment, OUT_FOR_DELIVERY order/assignment, current version and valid active challenge.

Success 200 returns the existing sanitized operations order snapshot with version incremented, DELIVERED, assignment deliveredAt, and `handoverVerified:true, alreadyCompleted:false`. No PIN/verifier/ciphertext is returned. An identical retry after a lost successful response, from the same still-authorized rider with the same PIN and original expectedVersion, returns 200 with `alreadyCompleted:true`; it performs no second delivery/consumption/event. Different PIN/version or historical delivered order without a challenge returns 409. The retry acknowledgement is permitted after challenge expiry because delivery already committed; it cannot cause another transition.

Customer issue/read and rider completion are throttled per authenticated user and HTTP method: 60 GET/minute and 30 POST/minute, shared across handover routes. This is supplementary in-process throttling; five-attempt and three-issue bounds persist in PostgreSQL across restarts. Use one backend process as already required by the Phase 7 outbox; distributed edge throttling is needed before horizontal scaling.

| HTTP | Meaning / Flutter behavior |
|---|---|
| 400 INVALID_REQUEST | Malformed body/PIN, unknown field, or incorrect PIN. Incorrect well-formed guesses consume an attempt. |
| 401 UNAUTHENTICATED | Session expired/revoked or account inactive. Reauthenticate. |
| 403 FORBIDDEN | Wrong role or not current assigned rider. |
| 404 NOT_FOUND | Missing order or customer ownership mismatch. |
| 409 REQUEST_FAILED | Stale version, unavailable/terminal state, missing/expired/invalidated/consumed challenge. Refresh authoritative REST data. |
| 429 RATE_LIMITED | Request throttle, lock, cooldown or exhausted issue quota. Customer GET provides state and nextIssueAt when permitted. |
| 503 SERVICE_UNAVAILABLE | Missing/bad keys, integrity/configuration problem or transaction/storage failure. Do not show success; retry safely or contact support. |

No typed handover error subcodes or Retry-After header are added; do not parse English text to decide delivery success. Refresh state after 409/429. In LOCKED, waiting alone does not unlock the old challenge; customer must explicitly regenerate after cooldown, within quota.

## Transactions, privacy and integration

All handover operations lock the order, then current assignment and challenge; session/role/assignment are revalidated in transaction. Valid verification atomically consumes the challenge, clears ciphertext, updates order and assignment, increments version, writes CONSUMED audit and ORDER_DELIVERED event, and enqueues OutboxEvent. Injected failure at any delivery write rolls all of this back. Wrong guesses return an outcome from the transaction and throw the HTTP error only after commit, so failed counts cannot roll back. Concurrent successes produce one event and one outbox row. Concurrent wrong attempts stop at five.

`deliver` is removed from transition definitions and availableActions. Both HTTP legacy `deliver` and direct `OperationsService.mutate(...,'deliver',...)` return 409; calling mutate with complete-handover is also blocked. For assigned riders at OUT_FOR_DELIVERY, availableActions now contains `complete-handover`. There is no admin/development skip path. Historical delivered orders remain readable.

Existing Socket.IO server and payment logic are unchanged. Successful handover emits the existing post-commit `order.updated` invalidation through the durable outbox, eventType ORDER_DELIVERED. No PIN fields appear in sockets, ordinary order/rider/admin APIs or OrderEvent metadata. Safe event metadata is only `{handoverVerified:true,challengeVersion}`. Issue/incorrect-attempt/regeneration do not change order version or emit order.updated; customer screens should refresh handover on resume or explicit refresh and may use bounded polling while active.

Antigravity Flutter work:
- Customer screen: GET on open/resume; explicit Issue/Regenerate buttons; show PIN only to owning customer while ACTIVE; countdown is display-only, server expiry authoritative. Never auto-issue on refresh. Do not persist PIN in local storage, diagnostics or analytics.
- Rider screen: render `complete-handover` as six-digit entry preserving zeros; submit current version and PIN; disable double-tap while pending. No client-generated delivery success or socket-authoritative local status mutation.
- On uncertain network outcome, retry identical completion payload or fetch order detail. Refetch REST after sockets/reconnect. Clear entry on confirmed completion and sign-out.
- Distinguish expired, locked, exhausted quota, assignment invalidation and unavailable states. Never expose a Skip OTP button. Existing Phase 7 Flutter end-to-end tests that press direct Deliver must be adapted; this backend-only task does not claim Flutter OTP integration is complete.

## Support exceptions

Support/admin should record a case with order ID, authenticated reporter, timestamps, current assignment, redacted error/state and relevant audit IDs. Verify identity and actual physical handover through approved operational channels; do not request or log the PIN, query/decrypt it for a rider, reset attempts, mark DELIVERED manually or alter payment state. Help the authenticated customer regenerate within normal bounds or restore connectivity/session. Exhausted quota or compromised keys/assignment requires documented engineering/operations review and a separately reviewed recovery workflow. No force-complete or quota-reset endpoint is implemented here. Never claim delivery or refund until authoritative workflows confirm it.

## Verification

See IMPLEMENTATION_STATUS.md for executed commands and results. Tests use only synthetic records in food_delivery_test and remove their own fixtures. PostgreSQL remains authoritative. Deployment is single-instance; this is not a claim of SMS OTP delivery, multi-instance rate limiting, key-ring rotation or completed Flutter UI.
