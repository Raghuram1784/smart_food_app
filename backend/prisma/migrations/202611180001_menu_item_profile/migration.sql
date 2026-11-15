-- Additive: structured food-family / taste profile for Smart Food Finder matching. No existing rows change.
CREATE TABLE "MenuItemProfile" (
    "menuItemId" VARCHAR(64) NOT NULL,
    "cuisine" VARCHAR(60) NOT NULL,
    "foodFamily" VARCHAR(60) NOT NULL,
    "dishGroup" VARCHAR(40) NOT NULL,
    "mainIngredient" VARCHAR(40) NOT NULL,
    "tasteTags" VARCHAR(20)[] NOT NULL DEFAULT ARRAY[]::VARCHAR(20)[],
    "spiceLevel" SMALLINT NOT NULL DEFAULT 0,
    "synonyms" VARCHAR(60)[] NOT NULL DEFAULT ARRAY[]::VARCHAR(60)[],
    "tagSource" VARCHAR(20) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "MenuItemProfile_pkey" PRIMARY KEY ("menuItemId"),
    CONSTRAINT "MenuItemProfile_spice_check" CHECK ("spiceLevel" BETWEEN 0 AND 3)
);
CREATE INDEX "MenuItemProfile_foodFamily_idx" ON "MenuItemProfile"("foodFamily");
CREATE INDEX "MenuItemProfile_dishGroup_idx" ON "MenuItemProfile"("dishGroup");
ALTER TABLE "MenuItemProfile" ADD CONSTRAINT "MenuItemProfile_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "MenuItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
