# Phase 5 order flow

## Cart and addresses

One persistent Cart row per customer (unique customerId), including an empty cart after checkout. No client-supplied customer identity. AuthGuard and CUSTOMER RolesGuard protect cart, addresses, quotes and orders. A per-customer User row lock and Serializable transactions serialize mutations; serialization conflicts retry up to four times. expectedVersion rejects stale edits rather than silently overwriting them. Identical item/variant/sorted-add-on selections merge, quantity 1–20, at most 20 selections. Add-ons apply once per unit; arbitrary add-on quantities are not supported. Switching restaurants requires an explicit replaceRestaurant flag plus the expected cart version and occurs atomically. Cart persistence survives logout.

Addresses belong to the verified customer, validate active PostgreSQL localities and use a partial unique default-address index. Updates use the full permitted address DTO. Removing an address does not alter historical orders. Serviceability checks the restaurant's configured locality zone only: no geocoding, exact street coverage or navigation claim.

## Pricing and accepted quotes

PricingService.selection is extracted from the existing single-meal method without changing its validation behavior. CartPricingService validates all actual cart lines, multiplies merchandise/customization amounts by quantity, then invokes the existing integer/BigInt calculator once with aggregate amounts. Current fixed packaging ₹10, delivery ₹20 and platform ₹5 apply once per order. Percentage rules use aggregate merchandise; tax applies to discounted merchandise using HALF_UP. Existing rule specificity, minimum subtotal, promotion eligibility and caps remain in effect. Missing required fee rules fail closed. Discovery single-meal behavior remains unchanged.

POST cart/quote accepts expectedVersion and a customer-owned addressId (optional promotion). The server stores a CartQuote bound to cart/version/address/promotion, a fingerprint of calculated lines, totals, address snapshot and chosen rule version, and an expiry of at most two minutes or the earliest chosen rule expiry. Response includes itemized lines, all fee components, rule adjustments, expiry and quoteId. Unavailable contents fail with 422; no invalid quote can be checked out. Flutter displays server amounts only.

## Atomic checkout and retries

POST orders accepts cartId, addressId, quoteId, idempotencyKey (UUID) and DEMO_NO_PAYMENT. Only development/test plus explicit DEMO_CHECKOUT_ENABLED=true permits checkout. Production and unconfigured environments fail closed. A key is scoped to the customer; a matching persisted request returns the original order even after its quote expires. Reuse with another payload returns 409.

Within the Serializable transaction: lock customer; revalidate active customer session; check prior idempotency result; verify owned cart and saved quote/version/expiry; revalidate live catalog/options/serviceability/address; recompute order-level totals; compare fingerprint; create order and immutable item/add-on/address/pricing snapshots; insert ORDER_CREATED; clear cart and increment version; commit before responding. Unique (customerId,idempotencyKey) and (cartId,cartVersion) additionally prevent duplicate order creation. A failed event insertion was injected in the test database to verify full rollback, including snapshots and cart contents.

Flutter generates one idempotency key per checkout attempt, disables double taps, and saves the exact pending request in native secure storage under the customer ID before sending. Network failures preserve that request; the cart offers Check previous checkout, and retries use the same key. Definitive stale/invalid quote errors require a fresh review. No password or bearer token is included in this pending record. Server ownership validation remains authoritative across account switches.

## Order records and access

New orders are PENDING_RESTAURANT / UNPAID / DEMO_NO_PAYMENT, currency INR. No fake provider transaction, paid receipt, acceptance or delivery event. Random order numbers contain no customer information. Historical names/options/unit prices and delivery address are snapshots; restrictive foreign keys prevent catalog deletion from destroying history. Customer history/detail filters by current user. Paginated owner inbox requires RESTAURANT_OWNER and active OWNER membership for that exact restaurant; it omits customer identity, phone and address snapshots. There are no order-status mutation routes.

API paths under /api/v1: GET/DELETE cart; POST cart/items; PATCH/DELETE cart/items/:id; POST cart/quote; GET/POST addresses; PATCH/DELETE addresses/:id; POST/GET orders; GET orders/:id; GET restaurants/:restaurantId/orders. DELETE cart/item requires expectedVersion in JSON. Lists use page and limit (1–30), newest first. Auth, ownership, validation and conflicts use the existing error envelope with HTTP 401/403/400/409/422.

## Future payments and operations

Phase 6 must add a server-verified provider payment lifecycle; only validated provider events may set PAID, with independent payment idempotency. Disable demo checkout in production. No card/banking data is collected here.

Phase 7 transition policy: owner with active membership may move PENDING_RESTAURANT to ACCEPTED/REJECTED, ACCEPTED to PREPARING, PREPARING to READY_FOR_PICKUP; an authorized assigned rider may move READY_FOR_PICKUP to PICKED_UP, then OUT_FOR_DELIVERY, then DELIVERED. Cancellation requires an explicit future policy including payment/refund handling; no customer status patch is currently allowed. Terminal statuses cannot advance. Implement compare-and-set transitions and actor authorization when those APIs are introduced.

OrderEvent is the small transactional outbox: ORDER_CREATED is inserted with the order and publishedAt remains null. A future worker claims committed rows using FOR UPDATE SKIP LOCKED, publishes with event ID and marks publication only after acknowledgement. Consumers deduplicate by event ID because a crash between publish/mark permits redelivery. No publisher or Socket.IO notification runs now. Expand the current per-order event-type uniqueness if future policy permits repeated event types. Cart updates are durable versioned state; no external cart-event stream is claimed.

## Data and scope

Only the existing synthetic Hyderabad catalog, generated demo users and explicitly synthetic addresses/orders are used. Existing food assets and their licensing records are reused; no new external datasets or Accurate Background data are accessed. No repository push, external publication, production deployment or destructive database reset occurs.
