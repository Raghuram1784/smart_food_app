-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "OperatingStatus" AS ENUM ('OPEN', 'CLOSED', 'PAUSED');

-- CreateEnum
CREATE TYPE "AvailabilityStatus" AS ENUM ('AVAILABLE', 'SOLD_OUT', 'UNAVAILABLE');

-- CreateEnum
CREATE TYPE "PricingComponent" AS ENUM ('PACKAGING', 'DELIVERY', 'PLATFORM', 'DISCOUNT', 'TAX');

-- CreateEnum
CREATE TYPE "RoundingMode" AS ENUM ('HALF_UP');

-- CreateTable
CREATE TABLE "Restaurant" (
    "id" VARCHAR(64) NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "slug" VARCHAR(160) NOT NULL,
    "description" TEXT NOT NULL,
    "address" TEXT,
    "latitude" DECIMAL(9,6),
    "longitude" DECIMAL(9,6),
    "rating" DECIMAL(3,2) NOT NULL,
    "reviewCount" INTEGER,
    "estimatedDeliveryMinutes" INTEGER NOT NULL,
    "estimatedDeliveryMaxMinutes" INTEGER NOT NULL,
    "deliveryAvailability" BOOLEAN NOT NULL DEFAULT false,
    "imageKey" VARCHAR(64) NOT NULL,
    "cuisineDescription" VARCHAR(160) NOT NULL,
    "operatingStatus" "OperatingStatus" NOT NULL DEFAULT 'OPEN',
    "isDemo" BOOLEAN NOT NULL DEFAULT true,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "Restaurant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Category" (
    "id" VARCHAR(64) NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "slug" VARCHAR(80) NOT NULL,
    "description" TEXT,
    "imageKey" VARCHAR(64) NOT NULL,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "Category_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Cuisine" (
    "id" VARCHAR(64) NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "slug" VARCHAR(80) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "Cuisine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RestaurantCuisine" (
    "restaurantId" VARCHAR(64) NOT NULL,
    "cuisineId" VARCHAR(64) NOT NULL,

    CONSTRAINT "RestaurantCuisine_pkey" PRIMARY KEY ("restaurantId","cuisineId")
);

-- CreateTable
CREATE TABLE "MenuSection" (
    "id" VARCHAR(100) NOT NULL,
    "restaurantId" VARCHAR(64) NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "MenuSection_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MenuItem" (
    "id" VARCHAR(64) NOT NULL,
    "restaurantId" VARCHAR(64) NOT NULL,
    "categoryId" VARCHAR(64) NOT NULL,
    "sectionId" VARCHAR(100) NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "description" TEXT NOT NULL,
    "basePricePaise" INTEGER NOT NULL,
    "imageKey" VARCHAR(64) NOT NULL,
    "isVegetarian" BOOLEAN NOT NULL,
    "availabilityStatus" "AvailabilityStatus" NOT NULL DEFAULT 'AVAILABLE',
    "availabilityReason" VARCHAR(200),
    "availabilityUpdatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "version" INTEGER NOT NULL DEFAULT 1,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "MenuItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MenuItemVariant" (
    "id" UUID NOT NULL,
    "menuItemId" VARCHAR(64) NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "priceAdjustmentPaise" INTEGER NOT NULL DEFAULT 0,
    "isAvailable" BOOLEAN NOT NULL DEFAULT true,
    "availabilityReason" TEXT,
    "availabilityUpdatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "MenuItemVariant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AddOn" (
    "id" UUID NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "pricePaise" INTEGER NOT NULL,
    "isAvailable" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "AddOn_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MenuItemAddOn" (
    "menuItemId" VARCHAR(64) NOT NULL,
    "addOnId" UUID NOT NULL,

    CONSTRAINT "MenuItemAddOn_pkey" PRIMARY KEY ("menuItemId","addOnId")
);

-- CreateTable
CREATE TABLE "DeliveryZone" (
    "id" VARCHAR(64) NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "isIllustrative" BOOLEAN NOT NULL DEFAULT true,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "DeliveryZone_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RestaurantDeliveryZone" (
    "restaurantId" VARCHAR(64) NOT NULL,
    "zoneId" VARCHAR(64) NOT NULL,
    "isEligible" BOOLEAN NOT NULL DEFAULT false,
    "estimatedMinutes" INTEGER,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "RestaurantDeliveryZone_pkey" PRIMARY KEY ("restaurantId","zoneId")
);

-- CreateTable
CREATE TABLE "PricingRule" (
    "id" UUID NOT NULL,
    "code" VARCHAR(80) NOT NULL,
    "restaurantId" VARCHAR(64),
    "zoneId" VARCHAR(64),
    "component" "PricingComponent" NOT NULL,
    "fixedPaise" INTEGER,
    "rateBasisPoints" INTEGER,
    "minimumSubtotalPaise" INTEGER NOT NULL DEFAULT 0,
    "maximumChargePaise" INTEGER,
    "priority" INTEGER NOT NULL DEFAULT 0,
    "rounding" "RoundingMode" NOT NULL DEFAULT 'HALF_UP',
    "promotionCode" VARCHAR(80),
    "isActive" BOOLEAN NOT NULL DEFAULT false,
    "effectiveFrom" TIMESTAMPTZ(3) NOT NULL,
    "effectiveUntil" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "PricingRule_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Restaurant_slug_key" ON "Restaurant"("slug");

-- CreateIndex
CREATE INDEX "Restaurant_operatingStatus_displayOrder_id_idx" ON "Restaurant"("operatingStatus", "displayOrder", "id");

-- CreateIndex
CREATE UNIQUE INDEX "Category_name_key" ON "Category"("name");

-- CreateIndex
CREATE UNIQUE INDEX "Category_slug_key" ON "Category"("slug");

-- CreateIndex
CREATE INDEX "Category_isActive_displayOrder_idx" ON "Category"("isActive", "displayOrder");

-- CreateIndex
CREATE UNIQUE INDEX "Cuisine_name_key" ON "Cuisine"("name");

-- CreateIndex
CREATE UNIQUE INDEX "Cuisine_slug_key" ON "Cuisine"("slug");

-- CreateIndex
CREATE INDEX "RestaurantCuisine_cuisineId_restaurantId_idx" ON "RestaurantCuisine"("cuisineId", "restaurantId");

-- CreateIndex
CREATE INDEX "MenuSection_restaurantId_displayOrder_idx" ON "MenuSection"("restaurantId", "displayOrder");

-- CreateIndex
CREATE UNIQUE INDEX "MenuSection_id_restaurantId_key" ON "MenuSection"("id", "restaurantId");

-- CreateIndex
CREATE UNIQUE INDEX "MenuSection_restaurantId_name_key" ON "MenuSection"("restaurantId", "name");

-- CreateIndex
CREATE INDEX "MenuItem_restaurantId_availabilityStatus_displayOrder_id_idx" ON "MenuItem"("restaurantId", "availabilityStatus", "displayOrder", "id");

-- CreateIndex
CREATE INDEX "MenuItem_categoryId_availabilityStatus_basePricePaise_idx" ON "MenuItem"("categoryId", "availabilityStatus", "basePricePaise");

-- CreateIndex
CREATE INDEX "MenuItem_sectionId_restaurantId_idx" ON "MenuItem"("sectionId", "restaurantId");

-- CreateIndex
CREATE UNIQUE INDEX "MenuItemVariant_menuItemId_name_key" ON "MenuItemVariant"("menuItemId", "name");

-- CreateIndex
CREATE INDEX "MenuItemAddOn_addOnId_idx" ON "MenuItemAddOn"("addOnId");

-- CreateIndex
CREATE UNIQUE INDEX "DeliveryZone_name_key" ON "DeliveryZone"("name");

-- CreateIndex
CREATE INDEX "RestaurantDeliveryZone_zoneId_isEligible_idx" ON "RestaurantDeliveryZone"("zoneId", "isEligible");

-- CreateIndex
CREATE UNIQUE INDEX "PricingRule_code_key" ON "PricingRule"("code");

-- CreateIndex
CREATE INDEX "PricingRule_restaurantId_zoneId_component_isActive_priority_idx" ON "PricingRule"("restaurantId", "zoneId", "component", "isActive", "priority");

-- AddForeignKey
ALTER TABLE "RestaurantCuisine" ADD CONSTRAINT "RestaurantCuisine_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RestaurantCuisine" ADD CONSTRAINT "RestaurantCuisine_cuisineId_fkey" FOREIGN KEY ("cuisineId") REFERENCES "Cuisine"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MenuSection" ADD CONSTRAINT "MenuSection_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MenuItem" ADD CONSTRAINT "MenuItem_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MenuItem" ADD CONSTRAINT "MenuItem_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "Category"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MenuItem" ADD CONSTRAINT "MenuItem_sectionId_restaurantId_fkey" FOREIGN KEY ("sectionId", "restaurantId") REFERENCES "MenuSection"("id", "restaurantId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MenuItemVariant" ADD CONSTRAINT "MenuItemVariant_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "MenuItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MenuItemAddOn" ADD CONSTRAINT "MenuItemAddOn_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "MenuItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MenuItemAddOn" ADD CONSTRAINT "MenuItemAddOn_addOnId_fkey" FOREIGN KEY ("addOnId") REFERENCES "AddOn"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RestaurantDeliveryZone" ADD CONSTRAINT "RestaurantDeliveryZone_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RestaurantDeliveryZone" ADD CONSTRAINT "RestaurantDeliveryZone_zoneId_fkey" FOREIGN KEY ("zoneId") REFERENCES "DeliveryZone"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PricingRule" ADD CONSTRAINT "PricingRule_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PricingRule" ADD CONSTRAINT "PricingRule_zoneId_fkey" FOREIGN KEY ("zoneId") REFERENCES "DeliveryZone"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Business invariants (Prisma does not yet represent CHECK constraints).
ALTER TABLE "Restaurant" ADD CONSTRAINT "Restaurant_values_check" CHECK (
 rating BETWEEN 0 AND 5 AND ("reviewCount" IS NULL OR "reviewCount" >= 0)
 AND "estimatedDeliveryMinutes" > 0 AND "estimatedDeliveryMaxMinutes" >= "estimatedDeliveryMinutes"
 AND ((latitude IS NULL AND longitude IS NULL) OR (latitude IS NOT NULL AND longitude IS NOT NULL AND latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)));
ALTER TABLE "MenuItem" ADD CONSTRAINT "MenuItem_price_version_check" CHECK ("basePricePaise" >= 0 AND version >= 1);
ALTER TABLE "MenuItemVariant" ADD CONSTRAINT "MenuItemVariant_price_check" CHECK ("priceAdjustmentPaise" >= 0);
ALTER TABLE "AddOn" ADD CONSTRAINT "AddOn_price_check" CHECK ("pricePaise" >= 0);
ALTER TABLE "RestaurantDeliveryZone" ADD CONSTRAINT "RestaurantDeliveryZone_minutes_check" CHECK ("estimatedMinutes" IS NULL OR "estimatedMinutes" > 0);
ALTER TABLE "PricingRule" ADD CONSTRAINT "PricingRule_values_check" CHECK (
 (("fixedPaise" IS NOT NULL)::int + ("rateBasisPoints" IS NOT NULL)::int) = 1
 AND ("fixedPaise" IS NULL OR "fixedPaise" >= 0)
 AND ("rateBasisPoints" IS NULL OR "rateBasisPoints" BETWEEN 0 AND 10000)
 AND "minimumSubtotalPaise" >= 0 AND ("maximumChargePaise" IS NULL OR "maximumChargePaise" >= 0)
 AND ("effectiveUntil" IS NULL OR "effectiveUntil" > "effectiveFrom"));
-- Trusted extension for case-insensitive substring search. Cloud operator must allow pg_trgm.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX "MenuItem_name_trgm" ON "MenuItem" USING gin (name gin_trgm_ops);
CREATE INDEX "MenuItem_description_trgm" ON "MenuItem" USING gin (description gin_trgm_ops);
CREATE INDEX "Restaurant_name_trgm" ON "Restaurant" USING gin (name gin_trgm_ops);
CREATE INDEX "Restaurant_cuisine_trgm" ON "Restaurant" USING gin ("cuisineDescription" gin_trgm_ops);
