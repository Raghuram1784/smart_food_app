-- F4 live tracking: one row per active delivery holding ONLY the latest rider fix (no history),
-- the customer's confirmed drop pin for that order and the last computed ETA. Rows are deleted
-- once the order is terminal.
CREATE TABLE "DeliveryTracking" (
  "orderId" UUID NOT NULL,
  "riderId" UUID,
  "latitude" DECIMAL(9,6),
  "longitude" DECIMAL(9,6),
  "accuracyMeters" DOUBLE PRECISION,
  "headingDegrees" DOUBLE PRECISION,
  "speedMps" DOUBLE PRECISION,
  "recordedAt" TIMESTAMPTZ(3),
  "receivedAt" TIMESTAMPTZ(3),
  "destLatitude" DECIMAL(9,6),
  "destLongitude" DECIMAL(9,6),
  "destConfirmedAt" TIMESTAMPTZ(3),
  "etaSeconds" INTEGER,
  "etaDistanceMeters" INTEGER,
  "etaSource" VARCHAR(16),
  "etaPhase" VARCHAR(24),
  "routeGeometry" JSONB,
  "etaComputedAt" TIMESTAMPTZ(3),
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(3) NOT NULL,
  CONSTRAINT "DeliveryTracking_pkey" PRIMARY KEY ("orderId"),
  CONSTRAINT "DeliveryTracking_fix_shape" CHECK (("latitude" IS NULL) = ("longitude" IS NULL) AND ("latitude" IS NULL) = ("recordedAt" IS NULL) AND ("latitude" IS NULL OR ("riderId" IS NOT NULL AND "accuracyMeters" IS NOT NULL))),
  CONSTRAINT "DeliveryTracking_fix_range" CHECK ("latitude" IS NULL OR ("latitude" BETWEEN -90 AND 90 AND "longitude" BETWEEN -180 AND 180 AND "accuracyMeters" >= 0)),
  CONSTRAINT "DeliveryTracking_dest_shape" CHECK (("destLatitude" IS NULL) = ("destLongitude" IS NULL) AND ("destLatitude" IS NULL OR ("destLatitude" BETWEEN -90 AND 90 AND "destLongitude" BETWEEN -180 AND 180))),
  CONSTRAINT "DeliveryTracking_eta_source" CHECK ("etaSource" IS NULL OR "etaSource" IN ('ROUTED','ESTIMATE')),
  CONSTRAINT "DeliveryTracking_eta_values" CHECK (("etaSeconds" IS NULL OR "etaSeconds" >= 0) AND ("etaDistanceMeters" IS NULL OR "etaDistanceMeters" >= 0))
);
ALTER TABLE "DeliveryTracking" ADD CONSTRAINT "DeliveryTracking_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE INDEX "DeliveryTracking_riderId_idx" ON "DeliveryTracking"("riderId");
