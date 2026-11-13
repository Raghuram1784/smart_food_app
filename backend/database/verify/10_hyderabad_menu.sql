-- Hyderabad menu items with category, cuisine breakdown, veg/non-veg totals, availability, and paise/rupee pricing.

-- 1. All menu items with restaurant, locality, category, price in paise & rupees, and availability
SELECT mi.id,
       mi.name,
       r.name AS restaurant,
       l.name AS locality,
       c.name AS category,
       mi."isVegetarian",
       mi."basePricePaise",
       ROUND(mi."basePricePaise"::numeric / 100, 2) AS price_rupees,
       mi."availabilityStatus",
       mi."availabilityReason",
       mi."imageKey"
FROM "MenuItem" mi
JOIN "Restaurant" r ON mi."restaurantId" = r.id
LEFT JOIN "Locality" l ON r."localityId" = l.id
JOIN "Category" c ON mi."categoryId" = c.id
ORDER BY l."displayOrder" NULLS LAST, r."displayOrder", mi."displayOrder", mi.id;

-- 2. Menu items grouped by category
SELECT c.id AS category_id,
       c.name AS category,
       COUNT(mi.id) AS item_count,
       COUNT(CASE WHEN mi."isVegetarian" THEN 1 END) AS veg_count,
       COUNT(CASE WHEN NOT mi."isVegetarian" THEN 1 END) AS nonveg_count,
       COUNT(CASE WHEN mi."availabilityStatus" = 'AVAILABLE' THEN 1 END) AS available_count,
       MIN(mi."basePricePaise") AS min_paise,
       MAX(mi."basePricePaise") AS max_paise,
       ROUND(MIN(mi."basePricePaise")::numeric / 100, 2) AS min_rupees,
       ROUND(MAX(mi."basePricePaise")::numeric / 100, 2) AS max_rupees
FROM "Category" c
LEFT JOIN "MenuItem" mi ON mi."categoryId" = c.id
GROUP BY c.id, c.name, c."displayOrder"
ORDER BY c."displayOrder", c.id;

-- 3. Menu items grouped by restaurant cuisine
SELECT cu.id AS cuisine_id,
       cu.name AS cuisine,
       COUNT(DISTINCT r.id) AS restaurant_count,
       COUNT(DISTINCT mi.id) AS item_count,
       COUNT(DISTINCT CASE WHEN mi."isVegetarian" THEN mi.id END) AS veg_count,
       COUNT(DISTINCT CASE WHEN NOT mi."isVegetarian" THEN mi.id END) AS nonveg_count
FROM "Cuisine" cu
LEFT JOIN "RestaurantCuisine" rc ON rc."cuisineId" = cu.id
LEFT JOIN "Restaurant" r ON r.id = rc."restaurantId"
LEFT JOIN "MenuItem" mi ON mi."restaurantId" = r.id
GROUP BY cu.id, cu.name
ORDER BY item_count DESC, cu.name;

-- 4. Vegetarian vs non-vegetarian totals
SELECT COUNT(CASE WHEN "isVegetarian" THEN 1 END) AS vegetarian_items,
       COUNT(CASE WHEN NOT "isVegetarian" THEN 1 END) AS nonvegetarian_items,
       COUNT(*) AS total_items
FROM "MenuItem";

-- 5. Item availability breakdown and non-available items with availabilityReason (e.g. seasonal Haleem / sold-out)
SELECT "availabilityStatus",
       COUNT(*) AS item_count
FROM "MenuItem"
GROUP BY "availabilityStatus"
ORDER BY "availabilityStatus";

SELECT mi.id,
       mi.name,
       r.name AS restaurant,
       mi."availabilityStatus",
       mi."availabilityReason"
FROM "MenuItem" mi
JOIN "Restaurant" r ON r.id = mi."restaurantId"
WHERE mi."availabilityStatus" <> 'AVAILABLE'
   OR mi."availabilityReason" IS NOT NULL
ORDER BY mi."availabilityStatus", r.name, mi.id;
