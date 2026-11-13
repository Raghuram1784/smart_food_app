# Phase 7.1: Secure OTP-Based Delivery Handover

## Overview

Phase 7.1 introduces cryptographic six-digit OTP verification for food delivery handover. Direct status mutation to `DELIVERED` is strictly blocked in both the REST controller and transactional service layer; physical handover is confirmed only upon successful verification of an authoritative, server-generated PIN.

---

## Architecture & Security Model

```
                    ┌────────────────────────────┐
                    │  Customer Flutter Client   │
                    └──────────────┬─────────────┘
                                   │
              1. GET/POST /handover│(issues/reads 6-digit PIN)
                                   ▼
┌─────────────────────────────────────────────────────────────┐
│                 Authoritative NestJS Server                 │
│                                                             │
│  - PIN Generation: 6-digit zero-padded cryptographic PIN    │
│  - Verifier: HMAC-SHA256(PIN, Order context, VERIFY_KEY)    │
│  - Display Seal: AES-256-GCM(PIN, AAD, ENCRYPTION_KEY)      │
│  - Lockout Protection: 5 failed attempts locks for 5 mins   │
│  - Issuance Limit: 5 PIN issuances max per order            │
│  - Cooldown: 30s minimum between PIN regenerations          │
│  - Direct Deliver Bypass: Blocked (409 ConflictException)   │
└──────────────┬──────────────────────────────▲───────────────┘
               │                              │
               │3. Live Event                 │2. POST /complete-handover
               │   "ORDER_DELIVERED"          │   { pin, expectedVersion }
               ▼                              │
┌────────────────────────────┐  Physical Handover ┌───────────────────────────┐
│  Customer Real-Time View   │ <───────────────── │  Rider Flutter Client     │
│  (PIN hidden, Verified)    │   Customer reads   │  (Enters 6-digit PIN)     │
└────────────────────────────┘   PIN to Rider     └───────────────────────────┘
```

### 1. Dual-Key Cryptography
- **Verification Key (`HANDOVER_HMAC_KEY`)**: Domain-separated HMAC-SHA256 verifier with constant-time equality check (`crypto.timingSafeEqual`) to prevent timing attacks.
- **Display Key (`HANDOVER_ENCRYPTION_KEY`)**: AES-256-GCM authenticated encryption with authenticated associated data (AAD) binding `orderId`, `assignmentId`, `boundRiderId`, `challengeVersion`, `keyVersion`, and `expiresAt`.
- Key separation ensures that compromise of the verifier does not reveal plaintext PINs, and tampering with ciphertext or AAD fails GCM authentication tag verification.

### 2. State Machine & Constraints
- Handover can only be issued and active when order is `OUT_FOR_DELIVERY` and assignment is `OUT_FOR_DELIVERY`.
- Prior to `OUT_FOR_DELIVERY`, handover state is `UNAVAILABLE`.
- States:
  - `NOT_ISSUED`: Order is out for delivery, PIN generation pending customer request.
  - `ACTIVE`: PIN issued and valid for 10 minutes.
  - `EXPIRED`: 10-minute TTL elapsed; customer can regenerate if issuance limit has not been reached.
  - `LOCKED`: 5 consecutive incorrect attempts entered; locked for 5 minutes.
  - `INVALIDATED`: Rider reassignment detected; previous PIN revoked.
  - `CONSUMED`: Handover completed atomically; PIN ciphertext erased (`encryptedPin: null`).

### 3. Atomic Multi-Table Transaction
When rider invokes `POST /operations/delivery/orders/:id/complete-handover`:
1. Acquires row locks (`SELECT ... FOR UPDATE`) on `Order`, `DeliveryAssignment`, and `DeliveryHandover`.
2. Verifies assignment binding, order status (`OUT_FOR_DELIVERY`), and optimistic concurrency (`expectedVersion === order.version`).
3. If PIN is incorrect:
   - Increments `failedAttempts` on `DeliveryHandover`.
   - Records `HandoverAudit` with action `INCORRECT_PIN` (or `LOCKED` if attempts >= 5).
   - Commits failed attempt count even though the operation fails with HTTP 400 (or 429).
4. If PIN is correct:
   - Updates `DeliveryHandover` (`verifiedAt`, `consumedAt`, `encryptedPin: null`, `completionExpectedVersion`, `completedOrderVersion`).
   - Updates `Order` status to `DELIVERED` and increments `version`.
   - Updates `DeliveryAssignment` status to `DELIVERED` and records `deliveredAt`.
   - Records `HandoverAudit` with action `CONSUMED`.
   - Creates `OrderEvent` with event type `ORDER_DELIVERED`.
   - Queues outbox notification for real-time WebSocket distribution (`order.updated`).

### 4. Direct Delivery Bypass Prevention
- `operations.service.ts` line 59:
  ```ts
  if (action === 'deliver' || action === 'complete-handover') {
    throw new ConflictException('Customer handover PIN verification is required');
  }
  ```
- The only authorized path to transition an order to `DELIVERED` is via `HandoverService.complete()`.

---

## Endpoints

| Method | Path | Role | Description |
|---|---|---|---|
| `GET` | `/api/v1/orders/:id/handover` | `CUSTOMER` | Retrieve current handover state and active PIN |
| `POST` | `/api/v1/orders/:id/handover/issue` | `CUSTOMER` | Explicitly issue or regenerate 6-digit delivery PIN |
| `POST` | `/api/v1/operations/delivery/orders/:id/complete-handover` | `DELIVERY_PARTNER` | Verify 6-digit PIN and complete delivery atomically |

---

## Flutter UI Integration

### Customer Order Details (`lib/features/commerce/customer_handover_card.dart`)
- **When NOT_ISSUED**: Prominent "Generate delivery PIN" action with guidance.
- **When ACTIVE**: Large bold monospace PIN with generous letter-spacing, live countdown timer ("Expires in mm:ss"), attempts counter, recipient warning notice, and "Regenerate PIN" action.
- **When EXPIRED**: Explanatory warning with "Request new PIN" button.
- **When LOCKED**: Security alert explaining lockout with cooldown details.
- **When DELIVERED**: Verified badge with check icon; plaintext PIN automatically hidden.

### Rider Delivery Operations (`lib/features/commerce/operations_screen.dart`)
- Available action button updated to **"Confirm delivery (PIN)"**.
- Opens `_HandoverPinDialog` with 6-digit numeric input supporting leading zeros.
- Enforces 6-digit length before enabling submission.
- Disables submission and shows loading indicator to prevent duplicate taps.
- Displays inline error feedback on invalid attempts or locks.
