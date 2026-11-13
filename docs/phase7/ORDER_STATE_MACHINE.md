# Phase 7 state machine

PostgreSQL is authoritative. Each action requires an authenticated current role and `expectedVersion` from the REST snapshot. Unknown DTO properties are rejected. The order row is locked, permissions and expected source state are checked, version increments, OrderEvent and OutboxEvent are inserted, then the transaction commits. Stale/duplicate/conflicting requests return 409 and do not insert duplicate events. Event/outbox failure rolls back the entire operation.

| Action | Actor | From | To |
|---|---|---|---|
| accept | Active OWNER membership | PENDING_RESTAURANT | ACCEPTED |
| reject + reason (5–300 chars) | Active OWNER membership | PENDING_RESTAURANT | REJECTED |
| start-preparing | Active OWNER membership | ACCEPTED | PREPARING |
| ready | Active OWNER membership | PREPARING | READY_FOR_PICKUP |
| assign + riderId | ADMIN dispatch scope | READY_FOR_PICKUP, unassigned | READY_FOR_PICKUP with assignment |
| pickup | Assigned active DELIVERY_PARTNER | READY_FOR_PICKUP | PICKED_UP |
| out-for-delivery | Assigned active DELIVERY_PARTNER | PICKED_UP | OUT_FOR_DELIVERY |
| deliver | Assigned active DELIVERY_PARTNER | OUT_FOR_DELIVERY | DELIVERED |

AWAITING_PAYMENT has no kitchen action. REJECTED, DELIVERED and existing CANCELED states cannot reenter the workflow. No cancellation/reassignment/refund endpoint is added. Admin has no implicit kitchen or rider permission.

## Payment eligibility

RAZORPAY_TEST acceptance requires PAID and a persisted CAPTURED test attempt with matching amount and provider payment reference, established only by the existing Phase 6 provider verification. A paid flag alone is insufficient. DEMO_NO_PAYMENT acceptance requires UNPAID, NODE_ENV development/test and the separate explicit DEMO_FULFILLMENT_ENABLED=true flag. Production always rejects demo fulfillment. Kitchen/rider actions never alter paymentStatus.

Rejection records the reason. If paymentStatus is PAID, refundReviewRequired=true is persisted; PAID remains PAID. This is a reconciliation obligation, not a refund confirmation or automatic refund request.

## Assignments and history

One DeliveryAssignment per order; a partial unique index permits at most one active assignment per rider. Admin assignment locks the rider row and validates ACTIVE account and current delivery role. Rider actions update order and assignment status together, with real pickup/delivery timestamps. No invented positions, routes or countdowns.

Order.version defaults to 1 on existing orders. Existing event sequence values remain null to preserve historical records; their timestamps/IDs provide legacy ordering. New checkout events use sequence 1; capture and operational events increment the order version. Unique (orderId, sequence) and existing (orderId, eventType) prevent duplicates. No historical orders are auto-transitioned.

## REST contract

All paths below `/api/v1/operations`, using existing response/error envelopes and opaque Bearer sessions:

- GET restaurant/orders?page=1; GET restaurant/orders/:id
- POST restaurant/orders/:id/{accept,reject,start-preparing,ready}
- GET delivery/orders?page=1; GET delivery/orders/:id
- POST delivery/orders/:id/{pickup,out-for-delivery,deliver}
- GET dispatch/orders?page=1; GET dispatch/riders
- POST dispatch/orders/:id/assign

Mutations accept `{expectedVersion}`; rejection additionally `reason`, assignment additionally `riderId`. Lists return 20 records/page, newest updated first, with total/page. REST details include availableActions and paymentEligible. Owner/admin responses omit customer delivery address; assigned rider responses contain the destination needed for fulfillment. Pickup address comes from the actual restaurant record. No client-selected actor or restaurant identity is trusted.
