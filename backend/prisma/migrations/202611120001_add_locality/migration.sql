-- CreateTable
CREATE TABLE "Locality" (
    "id" VARCHAR(64) NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "city" VARCHAR(80) NOT NULL,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "Locality_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "Locality_name_key" ON "Locality"("name");
CREATE INDEX "Locality_city_isActive_displayOrder_idx" ON "Locality"("city", "isActive", "displayOrder");
ALTER TABLE "Restaurant" ADD COLUMN "localityId" VARCHAR(64);
ALTER TABLE "Restaurant" ADD CONSTRAINT "Restaurant_localityId_fkey" FOREIGN KEY ("localityId") REFERENCES "Locality"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "Restaurant_localityId_operatingStatus_displayOrder_id_idx" ON "Restaurant"("localityId", "operatingStatus", "displayOrder", "id");
