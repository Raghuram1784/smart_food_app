-- A rider may hold at most one *active* assignment. Terminal states (DELIVERED, CANCELED,
-- REJECTED) must not block future dispatch. Narrowing a partial unique index cannot
-- conflict with existing rows.
DROP INDEX IF EXISTS "DeliveryAssignment_one_active_rider";
CREATE UNIQUE INDEX "DeliveryAssignment_one_active_rider" ON "DeliveryAssignment" ("riderId")
  WHERE status IN ('READY_FOR_PICKUP', 'PICKED_UP', 'OUT_FOR_DELIVERY');
