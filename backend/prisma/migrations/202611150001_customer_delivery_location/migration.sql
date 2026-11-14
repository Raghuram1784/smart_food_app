-- Additive: customer delivery coordinates and restaurant serviceability configuration.
-- No existing rows are modified; legacy addresses keep null coordinates.
CREATE TYPE "AddressLocationSource" AS ENUM ('DEVICE_GPS', 'CUSTOMER_MAP_PIN');

ALTER TABLE "CustomerAddress"
  ADD COLUMN "city" VARCHAR(80) NOT NULL DEFAULT '',
  ADD COLUMN "latitude" DECIMAL(9,6),
  ADD COLUMN "longitude" DECIMAL(9,6),
  ADD COLUMN "locationAccuracyMeters" DOUBLE PRECISION,
  ADD COLUMN "locationSource" "AddressLocationSource",
  ADD COLUMN "locationConfirmedAt" TIMESTAMPTZ(3),
  ALTER COLUMN "localityId" DROP NOT NULL;

ALTER TABLE "CustomerAddress"
  ADD CONSTRAINT "CustomerAddress_coordinates_paired" CHECK (("latitude" IS NULL) = ("longitude" IS NULL)),
  ADD CONSTRAINT "CustomerAddress_coordinates_range" CHECK (
    "latitude" IS NULL OR ("latitude" BETWEEN -90 AND 90 AND "longitude" BETWEEN -180 AND 180)),
  ADD CONSTRAINT "CustomerAddress_location_source_required" CHECK (("latitude" IS NULL) = ("locationSource" IS NULL)),
  ADD CONSTRAINT "CustomerAddress_accuracy_range" CHECK (
    "locationAccuracyMeters" IS NULL OR "locationAccuracyMeters" BETWEEN 0 AND 500);

ALTER TABLE "Restaurant"
  ADD COLUMN "pickupLocationVerifiedAt" TIMESTAMPTZ(3),
  ADD COLUMN "deliveryRadiusMeters" INTEGER;

ALTER TABLE "Restaurant"
  ADD CONSTRAINT "Restaurant_delivery_radius_range" CHECK (
    "deliveryRadiusMeters" IS NULL OR "deliveryRadiusMeters" BETWEEN 100 AND 50000),
  ADD CONSTRAINT "Restaurant_verified_pickup_has_coordinates" CHECK (
    "pickupLocationVerifiedAt" IS NULL OR ("latitude" IS NOT NULL AND "longitude" IS NOT NULL));
