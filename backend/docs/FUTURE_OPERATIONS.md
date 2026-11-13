# Future transactions and real-time operations — design only

These modules/entities are not implemented in Phase 2. Add them to this modular monolith when their business flows are authorized; avoid empty placeholder modules now. PostgreSQL is authoritative, NestJS owns validated state transitions, Flutter calls APIs, and FastAPI receives scoped context through NestJS without unrestricted database writes.

## Planned relational entities

| Domain | Proposed keys, relations and invariants |
| --- | --- |
| Identity | User UUID, unique normalized identity; Role and UserRole composite key; CustomerProfile userId unique; RestaurantOperator(userId,restaurantId) unique membership; DeliveryPartner userId unique, verified operational status; Address ownerId FK; RefreshSession userId FK, hashed token, expiresAt/revokedAt and rotation chain. Never plaintext refresh tokens. |
| Cart | Cart customerId and restaurantId FKs, version, active/converted; CartItem(cartId,itemId,customizationHash) unique with positive quantity; CartItemOption snapshots selected variant/add-on IDs; validate one restaurant per cart unless a future multi-order design is explicit. |
| Quotes/promotions | PricingSnapshot immutable UUID, cartVersion, currency INR, item/fee/discount/tax amounts, policy version and expiresAt; Promotion unique code, eligibility/limits; PromotionRedemption unique order/promotion and transactional usage limits. |
| Orders | Order UUID, customerId/restaurantId/quoteId FKs, unique scoped idempotency key, currency, status, version, committedAt; OrderItem preserves product/variant names, options, quantity and exact unit/line paise even if catalog changes; OrderTotal components immutable per revision; OrderStatusHistory unique(orderId,version), actor, previous/next state, reason and timestamp; RestaurantAcceptance and PreparationEvent linked to order. |
| Delivery | DeliveryAssignment orderId/partnerId FKs, assignment version and status; partial unique index for one active assignment per order; RiderStatus timestamps; PickupEvent/DeliveryEvent unique event IDs, verified actor and proof references. Location samples need separate retention/privacy policy. |
| Payments | PaymentAttempt orderId FK, attemptId UUID, unique gateway order/payment references, exact amount/currency and status; PaymentStatusHistory append-only; WebhookEvent unique(provider,eventId), signature-verification result, payload digest and processing status. Payment verification is server-side; client success is not proof. |
| Rescue | OrderException orderId FK/type/status; RecoveryProposal exceptionId FK, orderVersion, expiry and priced options; SubstitutionOption records current availability/price difference; CustomerApproval binds customer/order/version/proposal; AgentAction unique action ID and policy decision; ResolutionAudit append-only actor, inputs, authorization, outcome and committed version. |
| Reliability | IdempotencyRecord unique(actorId,operation,key), request hash, result/status/expiry; OutboxEvent UUID, aggregateId, aggregateVersion, type/schemaVersion, payload, committedAt, attempts/nextAttemptAt/publishedAt; ConsumerInbox unique(consumer,eventId) for side-effect deduplication. |

## State changes and concurrency

Authenticate and authorize each operation against resource ownership/membership. Validate the transition from current state (e.g. placed → accepted → preparing → ready → picked_up → delivered); cancellation/refund needs explicit permitted branches. Load fresh order/menu/quote state. Update with `WHERE id = ? AND version = expectedVersion`; increment version, append status/audit row and insert outbox event in the SAME database transaction. Zero updated rows yields 409 and latest-state reconciliation. Use locks or serializable transactions for contested allocations/limits, bounded retries on serialization failures, and no external HTTP calls inside long database transactions.

Idempotency binds actor, operation, key AND request hash; repeated same request returns saved result, different payload with same key is rejected. The operation and stored result commit atomically. Incoming verified payment webhooks deduplicate by unique gateway event ID; acknowledge only durable receipt. A payment amount mismatch cannot advance an order. Use reconciliation jobs for uncertain gateway outcomes; never infer success from a timeout.

## Socket.IO delivery

After the outbox transaction commits, a worker claims pending events (short `FOR UPDATE SKIP LOCKED` lease), publishes and marks attempts. Delivery is at least once: a crash after publish can repeat an event. Consumers deduplicate IDs and compare versions. Event shape: `{eventId,type,schemaVersion,orderId,orderVersion,occurredAt,data}`. Never announce a pre-commit change. A broker is unnecessary initially; multiple processes later require a shared socket adapter or appropriate routing, based on actual scale.

Authenticate handshake and every room subscription. `order:<uuid>` rooms admit only that customer, assigned restaurant operators, authorized delivery partner and scoped staff. Recheck access on token expiry/reassignment and remove stale subscriptions. Never let a client supply an arbitrary trusted user/role/room. Keep private customer/payment details out of broad events.

On reconnect, Flutter sends last seen order version/event cursor, fetches authoritative GET order state, then resumes events from a bounded durable replay window. If a gap/out-of-order version occurs, re-fetch; do not replay animations as business truth. Reconcile local UI to server state, display connection freshness, and discard duplicates. The GET snapshot remains sufficient if all socket messages were missed.

## AI Order Rescue boundaries

FastAPI proposes typed recovery options using scoped read context. NestJS verifies current item/variant availability, restaurant compatibility, allergies/customer preferences, exact price differences, policy limits and expected order version. Customer approval is required for substitutions/charges where policy requires consent. Commit only through ordinary authorized/idempotent business commands. Store proposal, approval, attempted action and actual transaction result. An LLM message is never proof that an item was changed or a refund succeeded. Use compensation/refund workflows for external side effects; do not claim a distributed atomic transaction.

Next phase: smart budget search can build on DB filters, but a final-payable budget requires authoritative pricing/zone eligibility first. Cart/checkout, persistence, secure Razorpay test payments, restaurant writes, live notifications and rescue follow those dependencies. No timers, synthetic delivery motion or fake order events exist today.
