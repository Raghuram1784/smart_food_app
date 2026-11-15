# F3 Scheduled Delivery — Team NeuroX

Implemented 2026-11-15 on `feature/f3-scheduled-delivery`, from fetched `origin/main` 35e50617b23698df1ff1bdfa5ec62d59bb1a960e. Fetched `company/main` 6793e50c12c7b7a80fc1d82109b1927f52ff868e had the same source tree. Initial working tree was clean. Previous feature branches are untouched. No merge or push performed.

## Behavior and policy

Immediate delivery remains the default. Normal and group checkouts may book a future delivery target with a ±5-minute window. Group negotiation totals, discounts and bill splits are unchanged. Checkout returns the same order contract plus schedule fields; its idempotency hash includes the chosen schedule, while omitted/NOW defaults preserve historical immediate retry hashes.

Restaurant policy lives in PostgreSQL: scheduleOpenMinute / scheduleCloseMinute (minutes after midnight IST), scheduleWeekdays (0 Sunday through 6 Saturday), schedulePrepMinutes and scheduleCapacity. Initial **synthetic demo policy** is 09:00–23:00 every day, 20-minute preparation, four orders per slot. These are explicit defaults, not claimed verified real-world opening hours; operators must configure each restaurant before a real deployment. Overnight opening intervals and holiday overrides are not yet supported. No unrelated restaurant-settings UI was added.

Normal slots use 15-minute alignment, seven calendar dates including today, and a ten-minute booking lead before preparation begins. Travel estimate is max(10, restaurant estimatedDeliveryMaxMinutes minus configured preparation minutes). Preparation begins and pickup completes within the opening interval; the whole target window must end before closing. CLOSED/PAUSED or non-delivering restaurants offer no slots. Existing item availability, address serviceability, quote freshness and pricing checks still run at checkout. Slot listing does not reserve capacity; a concurrent booking may return 409 and requires selecting again.

The per-restaurant row lock and Serializable checkout/retry boundary serialize slot reservations. Capacity counts every non-rejected/non-canceled order at that exact target, including awaiting-payment reservations. It is measured in orders per slot, not individual dishes or riders. Awaiting-payment reservations are not auto-expired; customer cancellation before preparation releases them. Accepted-offer pricing is locked at checkout, not re-negotiated on the future delivery date.

## Persistent fields and migration

`202611230001_scheduled_delivery` is additive, applied to development and isolated test PostgreSQL (18 migrations). It adds restaurant policy and Order fields:

| Field | Meaning |
|---|---|
| deliveryMode | NOW or SCHEDULED; historical rows default to NOW |
| scheduledDeliveryAt | Target arrival, UTC |
| deliveryWindowStart / End | Target minus/plus five minutes |
| preparationStartAt | Deadline/recommended time to begin preparation to meet the plan |
| expectedPickupAt | Kitchen readiness/pickup deadline derived from travel estimate |
| dispatchReleaseAt | Invitation gate: five minutes before pickup, never before preparation |
| actualDeliveryAt | Timestamp written atomically by successful OTP delivery; historical rows remain null |

SQL CHECK constraints enforce valid modes, complete schedule shapes, window boundaries and timing order. Query indexes support due work and capacity lookup. No prior migration, seed, catalog or historical record was rewritten. `scripts/f3-preserve.cjs before/after` compared hashes of all pre-existing columns for orders, items, events, assignments, payments, handovers, restaurants, menus, localities and group orders/proposals. All matched before creating new synthetic device-test data. Preserved counts: 10 orders, 14 items, 76 order events, 6 assignments, 5 payment attempts, 6 handovers, 38 restaurants, 737 dishes, 10 localities, 2 groups and 3 proposals.

## API contracts

Existing Bearer opaque session and roles apply; errors use the existing error envelope.

- `GET /api/v1/restaurants/:restaurantId/delivery-slots?date=YYYY-MM-DD` — CUSTOMER; returns date chips, available slots, serverTime, timezone Asia/Kolkata, remaining capacity and policy. Times in slot objects are UTC. Invalid/out-of-range date: 409; invalid DTO: 400.
- `POST /api/v1/orders` and `POST /api/v1/groups/:id/checkout` — existing bodies plus optional `deliveryMode: "SCHEDULED", scheduledDeliveryAt: "2026-11-16T14:30:00.000Z"`. The timestamp must be ISO UTC. A NOW request with a time, or SCHEDULED without a time, is rejected. Expired/impossible/full slots: 409. Caller cannot submit its own deadlines or capacity.
- `GET /api/v1/restaurants/:restaurantId/orders?deliveryMode=SCHEDULED&page=1&limit=20` — authorized owner only; server-side pagination of active scheduled orders, preventing older scheduled orders being hidden behind immediate orders.
- `GET /api/v1/operations/delivery/upcoming-scheduled` — active eligible online DELIVERY_PARTNER; at most twenty chronological previews, only restaurant name and target/pickup timestamps. No customer identity, exact address, PIN, order ID or accept action. Offline/busy riders receive an empty list.
- `POST /api/v1/orders/:id/cancel-scheduled`, `{expectedVersion: n}` — owning customer only, before preparationStartAt while awaiting payment/pending/accepted. Cancels transactionally and releases the slot; identical cancellation retries acknowledge the canceled order. Wrong customer: 404, role: 403, stale or too late: 409. A captured payment is marked refundReviewRequired, never REFUNDED. A capture arriving after cancellation also leaves the order canceled and flags review.

Ordinary customer/owner/rider order responses include `scheduleIndicator`. Existing rider offers additionally show target window and pickup time without revealing the full customer address before acceptance.

## Scheduler and correctness

`SchedulingService` runs every five seconds and immediately on initialization. It derives work from persisted order timestamps, not volatile timers. Each order is locked; events have unique (orderId,eventType) keys, version sequence and a transactional outbox. Multiple workers cannot duplicate a due event. Failures roll back and retry on the next sweep; restart catches up with overdue work. The existing Socket.IO outbox remains a single-process deployment component; scaling it still requires the existing shared-adapter/claim work.

The owner receives the ordinary ORDER_CREATED notification immediately after checkout. Early acceptance/rejection is allowed. `start-preparing` and `ready` cannot run before preparationStartAt, including direct backend calls. Preparing is manual, never an automatic status transition. Action lists hide premature preparation. Dispatch is gated in every offer generation/read/accept and admin fallback path. READY early orders remain queued until release. Invitation upsert/conditional renewal prevents scheduler/polling races from duplicating or reopening accepted/declined offers. One rider acceptance, existing pickup/out-for-delivery and secure OTP remain authoritative.

Events: SCHEDULE_PREPARATION_DUE, SCHEDULE_DISPATCH_DUE, SCHEDULE_AT_RISK, SCHEDULE_DELAYED, SCHEDULE_CANCELED. They use the existing minimal authorized order.updated payload; clients refetch REST. Screens show in-app notices and the persisted timeline. There is no SMS/OS push guarantee while the app is closed.

Indicators: Scheduled before preparation; Preparing while kitchen progress is on time; On track once progressing; At risk when required preparation/pickup/transit milestones are missing; Delayed after window end. Delivered within/outside window compares actual OTP completion against both inclusive boundaries. No invented GPS position, live route or guaranteed accuracy. A missed milestone produces one durable notification, not repeated spam. Recovery of current progress changes the computed indicator; prior audit notices remain in history.

## Flutter and development demo

New reusable SchedulePicker and ScheduleCard preserve existing themes and add animated expansion, date/time chips, explicit highlighted window, confirmation/My Orders badges, kitchen Scheduled Orders and rider previews. Customer cancellation has an explicit confirmation. UTC timestamps are displayed in IST regardless of device timezone. Checkout stays disabled until a slot is selected. REST remains authoritative on refresh, errors and Socket.IO reconnects.

`SCHEDULE_DEMO_FAST=true` works only for NODE_ENV=development: one-minute slots, one-minute prep/travel/lead and dispatch at pickup. It still validates all rules and keeps the ±5-minute target window. Before preparation, even this accelerated window is labeled Scheduled, not prematurely At risk. Production and test ignore the flag. Normal mode is false. Stored plans are immutable when the flag changes.

## Verification and evidence

Final command outcomes and Samsung result are recorded below after the verification run. No API/provider double is used in the device flow. Backend provider-result fixtures used for the late-capture test remain confined to food_delivery_test.

Reproduce device verification from the workspace:

1. Build backend; apply migrations. Start the development backend with demo checkout/fulfillment enabled and SCHEDULE_DEMO_FAST=true for this run only.
2. From backend, `npx tsx scripts/prepare-f3-device.ts` creates synthetic customer, owner and rider accounts and writes credentials only to ignored `build/f3-device-defines.json`.
3. `adb -s RZCWA12406A reverse tcp:5000 tcp:5000`; keep the Samsung unlocked.
4. `flutter drive --driver=test_driver/scheduled_delivery.dart --target=integration_test/scheduled_delivery_test.dart -d RZCWA12406A --no-pub --dart-define-from-file=build/f3-device-defines.json`.
5. The driver stores screenshots and a secret-free device-result.json here. The flow uses actual UI slot selection/checkout and invitation acceptance; kitchen/pickup/OTP actions use the same authorized REST APIs while switching UI roles. It waits for real backend timing gates and observes a separate customer Socket.IO session. It does not prove simultaneous use on multiple physical phones.
6. Restore normal backend scheduling and install the ordinary app build after testing. Never ship the integration-test APK or its private defines.

## Limits and review

Operating hours/capacity are configurable database policy; per-day exceptions, item-based kitchen capacity, automatic payment reservation expiry, rescheduling, external push and predictive/GPS ETA are not included. Cancellation closes when preparation is due; support must handle later exceptions through a separately authorized workflow, not an OTP bypass. No rider replacement, mandatory GPS, paid services or new dependencies were introduced. Existing manual dispatch fallback was preserved but is not mandatory and respects the same scheduled gate.

Review and approve the feature commit before merging. Do not push either remote until authorized.
