ALTER TABLE "Restaurant"
 ADD COLUMN "scheduleOpenMinute" INTEGER NOT NULL DEFAULT 540,
 ADD COLUMN "scheduleCloseMinute" INTEGER NOT NULL DEFAULT 1380,
 ADD COLUMN "schedulePrepMinutes" INTEGER NOT NULL DEFAULT 20,
 ADD COLUMN "scheduleCapacity" INTEGER NOT NULL DEFAULT 4,
 ADD COLUMN "scheduleWeekdays" INTEGER[] NOT NULL DEFAULT ARRAY[0,1,2,3,4,5,6],
 ADD CONSTRAINT "Restaurant_schedule_policy" CHECK ("scheduleOpenMinute" >= 0 AND "scheduleCloseMinute" <= 1440 AND "scheduleCloseMinute" > "scheduleOpenMinute" AND "schedulePrepMinutes" BETWEEN 1 AND 180 AND "scheduleCapacity" BETWEEN 1 AND 100 AND "scheduleWeekdays" <@ ARRAY[0,1,2,3,4,5,6]);
ALTER TABLE "Order"
 ADD COLUMN "deliveryMode" VARCHAR(16) NOT NULL DEFAULT 'NOW',
 ADD COLUMN "scheduledDeliveryAt" TIMESTAMPTZ(3),
 ADD COLUMN "deliveryWindowStart" TIMESTAMPTZ(3),
 ADD COLUMN "deliveryWindowEnd" TIMESTAMPTZ(3),
 ADD COLUMN "preparationStartAt" TIMESTAMPTZ(3),
 ADD COLUMN "expectedPickupAt" TIMESTAMPTZ(3),
 ADD COLUMN "dispatchReleaseAt" TIMESTAMPTZ(3),
 ADD COLUMN "actualDeliveryAt" TIMESTAMPTZ(3),
 ADD CONSTRAINT "Order_schedule_shape" CHECK (
 ("deliveryMode" = 'NOW' AND "scheduledDeliveryAt" IS NULL AND "deliveryWindowStart" IS NULL AND "deliveryWindowEnd" IS NULL AND "preparationStartAt" IS NULL AND "expectedPickupAt" IS NULL AND "dispatchReleaseAt" IS NULL)
 OR ("deliveryMode" = 'SCHEDULED' AND "scheduledDeliveryAt" IS NOT NULL AND "deliveryWindowStart" IS NOT NULL AND "deliveryWindowEnd" IS NOT NULL AND "preparationStartAt" IS NOT NULL AND "expectedPickupAt" IS NOT NULL AND "dispatchReleaseAt" IS NOT NULL AND "deliveryWindowStart" = "scheduledDeliveryAt" - INTERVAL '5 minutes' AND "deliveryWindowEnd" = "scheduledDeliveryAt" + INTERVAL '5 minutes' AND "preparationStartAt" < "expectedPickupAt" AND "expectedPickupAt" < "scheduledDeliveryAt" AND "dispatchReleaseAt" >= "preparationStartAt" AND "dispatchReleaseAt" <= "expectedPickupAt"));
CREATE INDEX "Order_deliveryMode_status_preparationStartAt_idx" ON "Order"("deliveryMode","status","preparationStartAt");
CREATE INDEX "Order_restaurantId_scheduledDeliveryAt_status_idx" ON "Order"("restaurantId","scheduledDeliveryAt","status");
