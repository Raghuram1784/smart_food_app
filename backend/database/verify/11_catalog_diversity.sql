-- Catalog diversity, summary totals, duplicate ID checks, price validity, and imageKey audit.

-- 1. Summary totals across all Phase 2.5 catalog entities
SELECT 'Restaurant' AS entity, COUNT(*) AS records FROM "Restaurant"
UNION ALL SELECT 'MenuItem', COUNT(*) FROM "MenuItem"
UNION ALL SELECT 'Category', COUNT(*) FROM "Category"
UNION ALL SELECT 'Locality', COUNT(*) FROM "Locality"
UNION ALL SELECT 'Cuisine', COUNT(*) FROM "Cuisine"
UNION ALL SELECT 'MenuSection', COUNT(*) FROM "MenuSection"
UNION ALL SELECT 'MenuItemVariant', COUNT(*) FROM "MenuItemVariant"
UNION ALL SELECT 'AddOn', COUNT(*) FROM "AddOn"
UNION ALL SELECT 'MenuItemAddOn', COUNT(*) FROM "MenuItemAddOn"
UNION ALL SELECT 'DeliveryZone', COUNT(*) FROM "DeliveryZone"
UNION ALL SELECT 'RestaurantDeliveryZone', COUNT(*) FROM "RestaurantDeliveryZone";

-- 2. Category diversity & vegetarian vs non-vegetarian totals
SELECT c.name AS category,
       COUNT(mi.id) AS dish_count,
       COUNT(CASE WHEN mi."isVegetarian" THEN 1 END) AS veg_count,
       COUNT(CASE WHEN NOT mi."isVegetarian" THEN 1 END) AS nonveg_count,
       MIN(mi."basePricePaise") AS min_paise,
       MAX(mi."basePricePaise") AS max_paise
FROM "Category" c
LEFT JOIN "MenuItem" mi ON mi."categoryId" = c.id
GROUP BY c.id, c.name, c."displayOrder"
ORDER BY c."displayOrder", c.id;

SELECT COUNT(CASE WHEN "isVegetarian" THEN 1 END) AS vegetarian_items,
       COUNT(CASE WHEN NOT "isVegetarian" THEN 1 END) AS nonvegetarian_items,
       COUNT(*) AS total_items
FROM "MenuItem";

-- 3. Duplicate identifier checks across catalog tables (expect zero rows)
SELECT 'Restaurant.id' AS check_name, id AS duplicate_value, COUNT(*) AS row_count FROM "Restaurant" GROUP BY id HAVING COUNT(*) > 1
UNION ALL
SELECT 'Restaurant.slug', slug, COUNT(*) FROM "Restaurant" GROUP BY slug HAVING COUNT(*) > 1
UNION ALL
SELECT 'MenuItem.id', id, COUNT(*) FROM "MenuItem" GROUP BY id HAVING COUNT(*) > 1
UNION ALL
SELECT 'Category.id', id, COUNT(*) FROM "Category" GROUP BY id HAVING COUNT(*) > 1
UNION ALL
SELECT 'Locality.id', id, COUNT(*) FROM "Locality" GROUP BY id HAVING COUNT(*) > 1
UNION ALL
SELECT 'Cuisine.id', id, COUNT(*) FROM "Cuisine" GROUP BY id HAVING COUNT(*) > 1;

-- 4. Price validity check: <= 0 paise prices on menu items or variant prices, or negative add-on prices (expect zero rows)
SELECT 'MenuItem' AS entity, id, name, "basePricePaise" AS price_paise
FROM "MenuItem"
WHERE "basePricePaise" <= 0
UNION ALL
SELECT 'AddOn', id::text, name, "pricePaise"
FROM "AddOn"
WHERE "pricePaise" < 0
UNION ALL
SELECT 'MenuItemVariant', v.id::text, mi.name || ' - ' || v.name, mi."basePricePaise" + v."priceAdjustmentPaise"
FROM "MenuItemVariant" v
JOIN "MenuItem" mi ON mi.id = v."menuItemId"
WHERE mi."basePricePaise" + v."priceAdjustmentPaise" <= 0;

-- 5. ImageKey audit: distinct keys in MenuItem and Category, plus unmapped/mismatched check
SELECT "imageKey",
       COUNT(*) AS menu_item_count,
       COUNT(CASE WHEN "isVegetarian" THEN 1 END) AS veg_count,
       COUNT(CASE WHEN NOT "isVegetarian" THEN 1 END) AS nonveg_count
FROM "MenuItem"
GROUP BY "imageKey"
ORDER BY "imageKey";

SELECT "imageKey",
       COUNT(*) AS category_count,
       STRING_AGG(id, ', ' ORDER BY "displayOrder", id) AS category_ids
FROM "Category"
GROUP BY "imageKey"
ORDER BY "imageKey";

-- Unmapped imageKeys or vegetarian items mapped to meat imagery (expect zero rows)
SELECT 'MenuItem_unmapped' AS issue, id, name, "imageKey"
FROM "MenuItem"
WHERE "imageKey" IS NULL
   OR BTRIM("imageKey") = ''
   OR "imageKey" NOT IN (
        'biryani', 'dosa', 'idli', 'paneer', 'pizza', 'pasta', 'burger', 'salad',
        'chicken-biryani', 'mutton-biryani', 'haleem', 'kebab',
        'noodles', 'meals', 'chaat', 'bakery', 'chai', 'dessert'
      )
UNION ALL
SELECT 'Category_unmapped', id, name, "imageKey"
FROM "Category"
WHERE "imageKey" IS NULL
   OR BTRIM("imageKey") = ''
   OR "imageKey" NOT IN (
        'biryani', 'dosa', 'idli', 'paneer', 'pizza', 'pasta', 'burger', 'salad',
        'chicken-biryani', 'mutton-biryani', 'haleem', 'kebab',
        'noodles', 'meals', 'chaat', 'bakery', 'chai', 'dessert'
      )
UNION ALL
SELECT 'MenuItem_veg_meat_photo', id, name, "imageKey"
FROM "MenuItem"
WHERE "isVegetarian" = true
  AND "imageKey" IN ('chicken-biryani', 'mutton-biryani', 'haleem', 'kebab');
