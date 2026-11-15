# Smart Food Delivery Application

A real-time, PostgreSQL-backed food delivery platform built with Flutter and NestJS for the Accurate AI recruitment hackathon.

Features an authentic Hyderabad-first marketplace (current development catalog: 38 restaurants, 737 dishes, 10 localities), server-authoritative exact pricing engine, opaque session RBAC authentication, versioned cart/address commerce, Razorpay test payment integration, and a real-time fulfillment pipeline powered by a transactional PostgreSQL outbox, authenticated Socket.IO, and live multi-role operational dashboards.

---

## Architecture Overview

```
                   ┌────────────────────────────────────────┐
                   │       Flutter Mobile Application       │
                   │ (Customer, Owner, Rider, Admin Roles)  │
                   └───────┬────────────────────────▲───────┘
                           │                        │
               REST / JSON │                        │ Invalidation
              (HTTP :5000) │                        │ Signals
                           ▼                        │
                   ┌────────────────────────────────┴───────┐
                   │             NestJS Backend             │
                   │ (Controllers, Services, Socket Gateway)│
                   └───────┬────────────────────────▲───────┘
                           │                        │
               Transaction │                        │ Dispatcher
                  Commits  │                        │ (1s loop)
                           ▼                        │
                   ┌────────────────────────────────┴───────┐
                   │          PostgreSQL Database           │
                   │ (Catalog, Orders, OutboxEvent, Audit)  │
                   └────────────────────────────────────────┘
```

- **Frontend (Flutter / Dart):**
  - Riverpod state management with auth-scoped providers.
  - GoRouter routing with declarative role gates.
  - Modern Editorial Food Light & Culinary Noir Dark themes with Bricolage Grotesque and Sora typography.
  - Official `socket_io_client` with transport reconnection backoff, background disconnection, and duplicate event deduplication.
  - Invalidation-first real-time architecture: incoming live events trigger authoritative REST snapshot refetches rather than speculative client state progression.
- **Backend (NestJS 11 / TypeScript):**
  - Modular architecture (`catalog`, `pricing`, `auth`, `commerce`, `payments`, `operations`, `areas`).
  - Strict validation pipes, global API exception envelopes, and request ID audit logging.
  - `@nestjs/platform-socket.io` gateway on shared port 5000 with opaque Bearer token handshake authentication and server-derived room assignment (`customer:{id}`, `restaurant:{id}`, `delivery:{id}`).
  - Periodic 15-second socket session revalidation; revoked or expired sessions immediately disconnect.
  - Durable `OutboxEvent` table populated within the same PostgreSQL transaction as operational order events, processed by a single-process dispatcher with exponential retry backoff.
- **Database (PostgreSQL / Prisma ORM):**
  - Eighteen forward-only Prisma migrations on `food_delivery_dev`.
  - Additive, highly normalized relational schema with custom composite search indexes.
  - Row-level concurrency locking (`expectedVersion`) on all mutation operations.

---

## Fulfillment & Operations Lifecycle (Phase 7 & Phase 7.1)

Orders progress through a strict, server-enforced state machine with cryptographic delivery handover verification:

```
[ PENDING_RESTAURANT ] ──(Owner Accept)──► [ ACCEPTED ] ──(Start Preparing)──► [ PREPARING ]
         │                                                                          │
   (Owner Reject)                                                                   │ (Mark Ready)
         ▼                                                                          ▼
   [ REJECTED ]                                                            [ READY_FOR_PICKUP ]
                                                                                    │
                                                                           (Automatic Rider Invitation)
                                                                                    ▼
    [ DELIVERED ] ◄──(Verify 6-Digit PIN)── [ OUT_FOR_DELIVERY ] ◄──(Pickup)── [ READY_FOR_PICKUP ] (Assigned)
          ▲
          │
    (Direct deliver bypass is strictly BLOCKED with 409 ConflictException)
```

### Role-Specific Interfaces

1. **Customer (`/orders/:id`):** Live 8-stage interactive Order Timeline with socket connection status indicator, copyable reference tags, itemized bill breakdowns, and the **Phase 7.1 Secure Handover Card** displaying the active 6-digit PIN with live expiry countdown, recipient advice, and re-issuance rate-limiting.
2. **Restaurant Owner (`/inbox/:id`):** Incoming orders inbox with pending count summary, read-only order details (excluding customer PII), and kitchen action buttons (`Accept`, `Reject` with mandatory reason, `Start preparing`, `Mark ready`).
3. **Rider dispatch:** eligible online riders receive automatic invitations; the first authorized acceptance wins. Admin assignment is not required.
4. **Delivery Partner (`/delivery`):** Active delivery console displaying pickup restaurant address and customer delivery destination, with action buttons (`Confirm pickup`, `Confirm delivery (PIN)` opening a 6-digit verification dialog with brute-force lockout protection).

---

## Hyderabad-First Marketplace (Phase 2.5 & Phase 3)

- **10 Service Localities:** Madhapur, Gachibowli, HITEC City, Kondapur, Kukatpally, Jubilee Hills, Banjara Hills, Ameerpet, Mehdipatnam, and Secunderabad.
- **28 Authentic Restaurants:** Curated representative menus featuring biryanis, tiffins, street chaats, haleem, Irani chai, and meals.
- **Authoritative Exact Pricing:**
  $$\text{Final Payable} = \text{Base Price} + \text{Variants} + \text{Add-ons} + \text{Packaging Fee} + \text{Delivery Fee} + \text{Platform Fee} + \text{GST} - \text{Discounts}$$
  Calculated with exact integer paise math on PostgreSQL; fees are applied once per order.

---

## Running the Application Locally

### Prerequisites

- Node.js 20+ and npm
- PostgreSQL 15+ running on `localhost:5432` with databases `food_delivery_dev` and `food_delivery_test`
- Flutter 3.24+ / Dart 3.5+ with Android SDK and an active Android emulator (`emulator-5554`)

### 1. Start the NestJS Backend

```powershell
cd backend
npm install
npm run db:generate
npm run db:migrate
npm run build
npm start
```
*The server starts on `http://localhost:5000` (API prefix: `/api/v1`, Socket.IO path: `/socket.io`).*

### 2. Run the Flutter Mobile App

In a second terminal:

```powershell
# Windows Unix socket temp directory workaround for Gradle
New-Item -ItemType Directory -Force -Path "build\jtmp" | Out-Null
$env:JAVA_TOOL_OPTIONS = '"-Djdk.net.unixdomain.tmpdir=C:\Users\Raghu Ram\Desktop\Smart_Food_App\build\jtmp"'

flutter pub get
flutter run -d emulator-5554
```

### 3. Demo Accounts

Passwords are generated locally in `backend/.env` (see `backend/.env.example`):
- **Customer:** `customer@demo.test`
- **Restaurant Owner:** `restaurant@demo.test` (Deccan Handi & Dum)
- **Delivery Partner:** `rider@demo.test`
- **Admin:** `admin@demo.test`

---

## Verification & Automated Test Suites

All tests run against real PostgreSQL instances with zero mocking of database constraints:

```powershell
# Backend unit tests (including F3 scheduling)
cd backend
npm test

# Backend full isolated E2E suite (including F3 scheduling)
npm run test:e2e

# Database schema & catalog verification
npm run db:verify

# Flutter static analysis & formatting
cd ..
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze

# Flutter unit & widget test suite
flutter test

# Android multi-role live operations E2E test on emulator
flutter drive `
  --driver=test_driver/operations.dart `
  --target=integration_test/operations_test.dart `
  -d emulator-5554 `
  --no-pub `
  --dart-define-from-file=build/auth-test-defines.json
```

---

## Documentation Index

- [Phase 2.5: Hyderabad Marketplace Strategy](docs/phase2_5/HYDERABAD_STRATEGY.md)
- [Phase 3: Smart Discovery & Pricing Engine](docs/phase3/PRICING_ENGINE.md)
- [Phase 4: Authentication & Opaque Session Architecture](docs/phase4/AUTHENTICATION_SPEC.md)
- [Phase 5: Commerce & Order Placement Flow](docs/phase5/ORDER_FLOW.md)
- [Phase 5.1: Implementation & Evidence Status](docs/phase5/IMPLEMENTATION_STATUS.md)
- [Phase 6: Razorpay Payment Integration](docs/phase6/PAYMENT_FLOW.md)
- [Phase 7: Real-Time Architecture & Outbox](docs/phase7/REALTIME_ARCHITECTURE.md)
- [Phase 7: State Machine Specification](docs/phase7/ORDER_STATE_MACHINE.md)
- [Phase 7: Implementation & Verification Status](docs/phase7/IMPLEMENTATION_STATUS.md)
- [Phase 7.1: Secure OTP Handover Specification](docs/phase7_1/SECURE_HANDOVER.md)
- [Phase 7.1: Implementation Status](docs/phase7_1/IMPLEMENTATION_STATUS.md)
- [Phase 7.1: Android Dual-Device Testing Guide](docs/phase7_1/ANDROID_TWO_DEVICE_TEST.md)
- [Asset Credits & Font Licenses](docs/ASSET_CREDITS.md)

---

## Current Status

F1 Smart Food Finder, F2 group ordering/negotiation/bill splitting, F7 automatic rider invitations/secure OTP and **F3 Scheduled Delivery** are implemented. F3 is on `feature/f3-scheduled-delivery`, pending review and merge approval.

At normal or group checkout, choose **Deliver Now** or **Schedule for Later**. Available slots come from PostgreSQL-backed restaurant hours, preparation/travel estimates and per-slot capacity. The selected ten-minute delivery window is a target, not a guarantee. All stored timestamps use UTC; Flutter displays IST.

The kitchen receives advance notice, accepts early and begins preparation when due. Rider invitations open only at the scheduled pickup stage. A restart-safe scheduler emits preparation/delay notifications through the existing authenticated Socket.IO outbox. Actual delivery time is recorded only by successful OTP handover. Historical orders and payments are preserved.

- [Current development handoff](docs/DEVELOPMENT_HANDOFF.md)
- [F3 contracts, verification, screenshots and limitations](docs/f3/IMPLEMENTATION.md)

For a rapid local demo, set `SCHEDULE_DEMO_FAST=true` only in a development server process. All timing validation, operating hours, capacity, role checks and OTP still apply. This setting is ignored in production and should normally be false.

No Kids Meals, rider replacement, rebranding, packaging or unrelated features are included. Merging and pushing to either GitHub repository require approval.
