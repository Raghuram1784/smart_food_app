-- Additive: per-serving nutrition with provenance. No existing rows change.
CREATE TYPE "NutritionBasis" AS ENUM ('ESTIMATE', 'LAB_TESTED', 'SUPPLIER_LABEL');
CREATE TABLE "MenuItemNutrition" (
    "menuItemId" VARCHAR(64) NOT NULL,
    "servingDescription" VARCHAR(120) NOT NULL,
    "servingGrams" INTEGER,
    "caloriesKcal" INTEGER NOT NULL,
    "proteinG" DECIMAL(6,1) NOT NULL,
    "carbsG" DECIMAL(6,1),
    "fatG" DECIMAL(6,1),
    "basis" "NutritionBasis" NOT NULL,
    "source" VARCHAR(300) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "MenuItemNutrition_pkey" PRIMARY KEY ("menuItemId"),
    CONSTRAINT "MenuItemNutrition_values_check" CHECK ("caloriesKcal" BETWEEN 0 AND 5000 AND "proteinG" >= 0 AND ("carbsG" IS NULL OR "carbsG" >= 0) AND ("fatG" IS NULL OR "fatG" >= 0) AND ("servingGrams" IS NULL OR "servingGrams" > 0))
);
ALTER TABLE "MenuItemNutrition" ADD CONSTRAINT "MenuItemNutrition_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "MenuItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
