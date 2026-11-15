-- Additive: a brand can operate several outlets (each outlet stays a Restaurant row with its own
-- locality, menu, delivery zones, owner memberships and orders). No existing rows change.
CREATE TABLE "RestaurantBrand" (
    "id" VARCHAR(64) NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "RestaurantBrand_pkey" PRIMARY KEY ("id")
);
ALTER TABLE "Restaurant" ADD COLUMN "brandId" VARCHAR(64);
ALTER TABLE "Restaurant" ADD CONSTRAINT "Restaurant_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES "RestaurantBrand"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "Restaurant_brandId_idx" ON "Restaurant"("brandId");
