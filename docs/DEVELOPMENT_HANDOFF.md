# Development Handoff

State of the Smart Food App after **F1 (Smart Food Finder)**, **F7 (secure OTP handover, GPS-free rider dispatch)** and **F2 (Group Food Ordering with restaurant price negotiation and bill splitting)**.
**F3 — Scheduled Delivery is implemented on `feature/f3-scheduled-delivery`.** See [F3 implementation and verification](f3/IMPLEMENTATION.md) for contracts, scheduling policy and device evidence.

---

## 1. Repository layout

| Path | What it is |
|---|---|
| `lib/` | Flutter app (single app; role-based UI for customer, restaurant owner, rider, admin) |
| `lib/app.dart` | GoRouter routes and role guards |
| `lib/core/`, `lib/shared/` | Theme, API client (Dio), shared widgets |
| `lib/features/<feature>/` | Feature modules (see §2) |
| `backend/` | NestJS API (`/api/v1`), Prisma 7 + PostgreSQL |
| `backend/src/modules/<module>/` | NestJS modules (see §3) |
| `backend/prisma/schema.prisma` | Data model; migrations in `backend/prisma/migrations/` |
| `backend/test/` | `*.unit.test.ts` (pure) and `*.e2e.test.ts` (isolated test DB) |
| `test/` | Flutter widget/unit tests |
| `docs/` | Phase notes, validation, screenshots |

## 2. Flutter architecture

- **State:** Riverpod 3 (`Provider`, `FutureProvider.autoDispose.family`, `Notifier`). No business pricing in the app: totals always come from the backend.
- **Navigation:** GoRouter in `lib/app.dart`. Group routes: `/groups`, `/groups/:id` (`?invite=1` opens the share sheet), `/group/:token` (invite deep link), `/owner/group-proposals`.
- **Networking:** `CommerceRepository.request(method, path, body)` (Dio, bearer session). API base from `--dart-define=API_BASE_URL=...`. For a USB device: `adb reverse tcp:5000 tcp:5000` and `API_BASE_URL=http://127.0.0.1:5000/api/v1/`.
- **Realtime:** `lib/features/commerce/live_orders.dart` (Socket.IO). Events are content-free (`order.updated`, `group.updated`, `group.proposals`); clients refetch over authenticated REST. Never put OTPs or prices in socket payloads.
- **Feature folders:** `auth`, `catalog`, `commerce` (cart, checkout, orders), `discovery` (Home), `finder` (F1 AI finder), `group` (F2), `location`, `operations` (owner and rider consoles), `pricing`, `profile`, `restaurant`, `navigation`.

## 3. NestJS modules

`areas`, `auth` (sessions, RBAC roles CUSTOMER / RESTAURANT_OWNER / DELIVERY_PARTNER / ADMIN), `catalog`, `categories`, `cuisines`, `menu`, `restaurants`, `pricing` (`CartPricingService` — the single source of pricing), `commerce` (cart, orders, demo checkout, idempotency), `payments` (Razorpay, demo mode), `operations` (owner and rider workflows, delivery offers, secure OTP handover, `OrderGateway` Socket.IO), `food-finder` (F1, Gemini), `group` (F2), `health`.

## 4. Prisma migrations (in order)

`202611110001_catalog` → `…120001_add_locality` → `…120002_auth` → `…120003_commerce` → `…130001_payments` → `…130002_operations` → `…130003_secure_handover` → `…140001_rider_presence` → `…140002_active_assignment_index` → `…150001_customer_delivery_location` → `…160001_delivery_offers` → `…170001_menu_item_nutrition` → `…180001_menu_item_profile` → `…190001_restaurant_brand` → **`…200001_group_ordering`** → **`…210001_group_bill_split`** → **`…220001_group_guest_participants`** → **`…230001_scheduled_delivery`**.

Apply with `npx prisma migrate deploy` (never `migrate reset` on the dev DB; it holds demo orders and 28 restaurant-owner accounts).

## 5. Features delivered

### F1 — Smart Food Finder
Budget- and diet-aware dish finder plus conversational AI (Gemini via `@google/genai`). Gemini only parses intent and phrases replies; prices, availability and totals are computed and verified by the backend against the live catalog. It falls back to the deterministic engine when Gemini is unavailable. The finder is rate limited (`FINDER_RATE_PER_MINUTE`).

### F7 — Secure handover and GPS-free dispatch
Delivery offers go to online riders by locality (no rider GPS). The customer's delivery location is optional, never forced. Handover uses a customer OTP stored as an HMAC and encrypted at rest; it is shown only to the customer and verified on `complete-handover`. TTL and regeneration are controlled by the `HANDOVER_*` settings.

### F2 — Group Food Ordering (`backend/src/modules/group`, `lib/features/group`)

- **Entry points:** a compact **Group Order** button under the Home search bar (start, join with a code, or resume an active group; the restaurant is chosen after starting) and "Start a group order" on every restaurant page.
- **Two ways to order (same group infrastructure):**
  - **Order for friends:** the organizer types participant names (`POST /groups/:id/guests`). Guests are `GroupMember` rows with `isGuest = true` and no account (`accountId` NULL, enforced by a check constraint), so they need no app, invite or OTP. The organizer adds food for each guest (`forMemberId` on `POST /groups/:id/items`), edits their lines and can remove a guest (`DELETE /groups/:id/guests/:guestId`), which removes their food and bumps the cart revision. Guests count toward the 12-person limit and appear in both bill splits.
  - **Invite friends:** the existing join code and link; each friend adds their own food. Both can be mixed in one group. Account holders' lines can only be changed by their owner.
- **Flow:**
  1. The organizer creates a group for one restaurant and a delivery address.
  2. The organizer shares an 8-character join code or a link. Invites are stored as SHA-256 hashes, and join attempts are limited to 10 per minute per user.
  3. Members add their own dishes to the shared cart.
  4. The organizer locks the cart.
  5. The organizer proposes a group price.
  6. The restaurant owner accepts, rejects or counters.
  7. The organizer accepts or declines the counter.
  8. The organizer checks out one normal order at the agreed price. That order then follows the regular owner → rider → OTP pipeline.
- **States:**
  - Group: `OPEN → LOCKED → PROPOSED → (COUNTERED) → ACCEPTED → ORDERED`, plus `REJECTED`, `CANCELED` and `EXPIRED`.
  - Proposal: `PENDING`, `ACCEPTED`, `COUNTERED`, `REJECTED`, `EXPIRED`, `WITHDRAWN`, `DECLINED`, `USED`.
  - At most one live proposal per group (partial unique index).
  - Expiry is applied lazily on read and write.
- **Concurrency:** Serializable transactions, `FOR UPDATE` locks and optimistic `expectedVersion` / `expectedRevision` checks. A conflict returns 409; serialization failures (P2034, 40001) are retried. Checkout is idempotent (`idempotencyKey`), and the proposal becomes `USED` exactly once.
- **Alternatives:** when a restaurant rejects, `GET /groups/:id/alternatives` lists other outlets of the same brand or nearby restaurants that can price the same cart. `POST /groups/:id/switch` moves the group there.

#### Group billing and negotiated pricing rules

- All money is in **integer paise**, and the backend is authoritative. The normal total comes from `CartPricingService` (items + customization + packaging + delivery + platform + tax − promotion).
- **Negotiation limits:**
  - The proposed total must be below the normal total, and the reduction must be ≤ the restaurant's `maxGroupDiscountBps` (default 3000 = 30%).
  - The restaurant can turn negotiation off with `groupNegotiationEnabled`.
  - A counteroffer must lie between the proposal and the normal total.
- **Limits and windows:**

  | Rule | Value |
  |---|---|
  | Max members | 12 |
  | Open groups per organizer | 3 |
  | Group lifetime | 120 min (30–240) |
  | Restaurant response window | 15 min |
  | Accepted offer validity | 30 min |
  | Counter response window | 15 min |
  | Proposals per group | 5 |
  | Proposals per restaurant | 3 |

- **Invalidation:** an accepted offer is valid only for the exact cart revision and restaurant it was agreed on. Any cart change, unlock or switch invalidates it.
- **The order:** the negotiated reduction is stored in `Order.discountPaise`, which satisfies the `Order_valid_amounts` check, with an audit copy in `Order.negotiatedDiscountPaise` and a link through `Order.groupProposalId` (unique).
- **Ownership and RBAC:** only the organizer locks, proposes, accepts and checks out; the organizer pays the whole order. Members edit only their own lines. The owner endpoints require `RESTAURANT_OWNER` membership of that outlet; owners of other brands get 403 or 404.

#### Bill splitting (`bill-split.ts`)

- **Informational only:** the organizer pays; members owe the organizer their share.
- **Methods** (organizer-only, `POST /groups/:id/split`):
  - **BY_PERSON (default):** each food line goes to its owner, or, if shared (`PATCH /groups/:id/items/:itemId/share`, organizer or item owner), is divided evenly between the chosen active members, so it is never charged twice. Fees, tax and discounts are allocated in proportion to each person's food.
  - **EQUAL:** the payable is divided equally.
- **Rounding:** largest remainder, ties broken by member join order. Shares are deterministic, non-negative and sum **exactly** to the payable. The server asserts this and throws otherwise.
- **Basis:**
  - `ESTIMATE`: normal total, before any agreement.
  - `AGREED`: a valid accepted offer exists for the current cart revision.
  - `FINAL`: a snapshot frozen at checkout (`GroupOrder.splitSnapshot`).
- **Membership:** removed or left members drop out automatically. A shared line whose sharers have all left falls back to its owner, or else to everyone. Members with zero items owe nothing under BY_PERSON.
- **Edge case:** if rounding could ever push a share below zero, the whole payable is re-split proportionally.

## 6. Test commands

| What | Command |
|---|---|
| Prisma validation | `cd backend && npx prisma validate` |
| Backend build | `cd backend && npm run build` |
| Backend unit | `cd backend && npm test` |
| Backend e2e | `cd backend && npm run test:e2e` (uses `TEST_DATABASE_URL` only — an isolated test database; never the dev DB) |
| F2 only | `cd backend && npx tsx --test test/group-ordering.e2e.test.ts test/bill-split.unit.test.ts` |
| Flutter analyze | `flutter analyze` |
| Flutter tests | `flutter test` (F2: `test/group_test.dart`) |
| Run on a device | `flutter run -d <device> --dart-define=API_BASE_URL=http://127.0.0.1:5000/api/v1/` after `adb reverse tcp:5000 tcp:5000` |

## 7. Environment variables (names only — values live in the git-ignored `backend/.env`)

- **Core:** `NODE_ENV`, `PORT`, `API_PREFIX`, `LOG_LEVEL`, `CORS_ORIGINS`, `DATABASE_URL`, `DIRECT_URL`, `TEST_DATABASE_URL`, `APP_LINK_BASE`
- **Auth / demo:** `AUTH_SESSION_HOURS`, `DEMO_AUTH_ENABLED`, `DEMO_CHECKOUT_ENABLED`, `DEMO_FULFILLMENT_ENABLED`, `DEMO_PASSWORD`, `DEMO_CUSTOMER_PASSWORD`, `DEMO_RESTAURANT_PASSWORD`, `DEMO_RIDER_PASSWORD`
- **Handover:** `HANDOVER_ENCRYPTION_KEY`, `HANDOVER_HMAC_KEY`, `HANDOVER_KEY_VERSION`, `HANDOVER_TTL_SECONDS`, `HANDOVER_REGENERATE_SECONDS`
- **Payments:** `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`
- **AI finder:** `GEMINI_API_KEY`, `GEMINI_MODEL`, `GEMINI_FALLBACK_MODEL`, `GEMINI_TIMEOUT_MS`, `FINDER_RATE_PER_MINUTE`, `FINDER_NEAR_BUDGET_PCT`
- **Scheduling:** `SCHEDULE_DEMO_FAST` (development only; false normally)
- **Flutter (`--dart-define`):** `API_BASE_URL`, `CATALOG_MODE`

Never commit `.env`, keys, tokens, GPS logs or customer data.

## 8. Branch workflow

- **Company repository (primary):**
  - `Accurate-Hackathon/KL-NeuroX` is private, with default branch `main`.
  - One feature branch per phase (`feature/f2-group-ordering`, `feature/f3-scheduled-delivery`, `feature/f4-live-tracking-eta`), created from the latest `main`. Feature branches are kept after merging.
  - Every change goes through a pull request that is reviewed before merging. No force-pushes, no direct commits to `main`, and no branch deletion without agreement.
  - Branch protection isn't available on the current GitHub plan, so the review discipline is manual.
- **Personal repository:** `Raghuram1784/smart_food_app` (public) receives the same reviewed feature PRs. Each repository gets its own merge commit, so the two `main` branches have identical files under different commit hashes.

## 9. Known limitations

- **Payments:** demo no-payment checkout and existing Razorpay TEST mode; group checkout remains demo-only. Members' shares are informational. Scheduled cancellation flags captured payments for review, never claims a refund.
- **Group size and lifetime:** a group can be ordered from one restaurant at a time, with up to 12 members and expiry measured in minutes.
- **Negotiation:** proposals are manual; there is no automatic pricing engine on the restaurant side.
- **Location:** rider GPS is shared only during an accepted active delivery (F4); dispatch never needs GPS. None of the 38 outlets has a confirmed pickup point yet, so owners must set one before the restaurant marker appears. Road routing uses the public OSRM demo in development only; without routing the ETA is a labelled estimate. Map tiles default to OpenStreetMap (development only).
- **Two-phone testing:** simultaneous rider/customer GPS movement on two physical phones will be completed after deployment; device verification so far used one Samsung sequentially.
- **Notifications:** push notifications aren't configured; in-app Socket.IO only. No SMS.
- **Branch protection:** unavailable on the current company GitHub plan.

## 10. Deployment

Proposal: [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md). Selected platform: **Microsoft Azure** (App Service + Azure Database for PostgreSQL + Flutter release APK); not deployed yet. `backend/.env.production.example` lists the App Service settings; `render.yaml` is kept only as an alternative. Decisions still needed: Azure tiers, map-tile and routing keys, and the payment mode for the live demo (Razorpay test mode recommended).

## 11. F3 — Scheduled Delivery

Normal and negotiated group checkout accept optional `deliveryMode: SCHEDULED` and `scheduledDeliveryAt` (ISO UTC). Omitting them preserves immediate delivery and old idempotency hashes. Slot availability comes from `GET /restaurants/:restaurantId/delivery-slots?date=YYYY-MM-DD`; checkout revalidates and reserves capacity atomically. Group prices and frozen bill splits remain unchanged.

Additive migration `202611230001_scheduled_delivery` adds restaurant operating-hour/preparation/capacity policy and order schedule timestamps. It is applied to development and isolated test databases; 18 migrations total. No catalog reseed or historical order/payment rewrite was performed. This checkout's development catalog contains 38 restaurants / 737 menu items / 10 localities.

`backend/src/modules/scheduling/` contains shared slot validation and a PostgreSQL-backed five-second scheduler. Restaurant/order row locks, Serializable checkout retries and unique event/offer constraints prevent overbooking and duplicated jobs. Scheduled owners receive the ordinary creation notification immediately, may accept early, and must wait until preparationStartAt to begin cooking. READY orders cannot dispatch until dispatchReleaseAt. The existing invitation acceptance, pickup and OTP flow remains authoritative.

Flutter reuses the green/cream/gold theme: Deliver Now / Schedule for Later, date chips, available time chips, target window, Scheduled Orders kitchen filter, restricted rider previews and schedule cards on confirmation, history and operations. UTC values always render in IST. Delay notifications use the authenticated durable order.updated outbox and existing screen refetches. No live GPS or guaranteed ETA is claimed.

`SCHEDULE_DEMO_FAST=true` only works when `NODE_ENV=development`; it shortens prep/travel/slots for demos but never skips hours, capacity, lead time, authorization or OTP. Keep it false normally. Existing booked timestamps do not change when this setting changes.

New commands: `cd backend; npx tsx --test test/scheduling.unit.test.ts test/scheduling.e2e.test.ts`; `flutter test test/scheduling_test.dart`. Full suite commands in section 6 include F3 automatically. Device reproduction, final results and limitations are in [docs/f3/IMPLEMENTATION.md](f3/IMPLEMENTATION.md).

F3 is merged into `main` in both repositories.


## 12. F4 — Live Rider Tracking and Smart ETA

Module `backend/src/modules/tracking/` (migration `202611240001_live_tracking`, 19 migrations total): `POST /tracking/orders/:id/location` (assigned rider, active delivery only; invalid, future, stale, out-of-order and too-frequent fixes rejected), `GET /tracking/orders/:id` (customer, assigned rider, outlet owner, admin), `PUT /tracking/orders/:id/destination` (customer pin) and `PUT /tracking/restaurants/:id/pickup-location` (owner). `DeliveryTracking` keeps only the latest fix per order and is deleted once the order is terminal. Socket event `delivery.location` goes only to the order's customer, rider and dispatch rooms.

Smart ETA (`eta.ts`, `routing.ts`) combines kitchen state, the rider's latest real fix, road routing (`ROUTING_PROVIDER=none|osrm`, `ROUTING_BASE_URL`) and the scheduled window; routing is requested at most every 45 s per order and failures retry after 15 s without overwriting a road route. Without routing the ETA is labelled Estimate and straight-line distance is never shown as road distance.

Flutter: `lib/features/tracking/` (rider sharing with foreground service, rider panel, Track Order screen, owner pickup point). Tests: `cd backend; npx tsx --test test/tracking.unit.test.ts test/tracking.e2e.test.ts`; `flutter test test/tracking_test.dart`. Details: [docs/f4/IMPLEMENTATION.md](f4/IMPLEMENTATION.md). F4 is merged into `main` in both repositories.
