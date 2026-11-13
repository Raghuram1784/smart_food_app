-- All restaurants with home locality, operatingStatus, serviceable zone count, menu item count, and photo check.

-- 1. Restaurant directory with locality, delivery window, serviceable zones, and menu counts
SELECT r.id,
       r.name,
       l.name AS locality,
       r.rating,
       r."estimatedDeliveryMinutes",
       r."estimatedDeliveryMaxMinutes",
       r."operatingStatus",
       r."deliveryAvailability",
       r."imageKey",
       COUNT(DISTINCT CASE WHEN rz."isEligible" THEN rz."zoneId" END) AS serviceable_zone_count,
       COUNT(DISTINCT mi.id) AS menu_item_count
FROM "Restaurant" r
LEFT JOIN "Locality" l ON r."localityId" = l.id
LEFT JOIN "RestaurantDeliveryZone" rz ON rz."restaurantId" = r.id
LEFT JOIN "MenuItem" mi ON mi."restaurantId" = r.id
GROUP BY r.id, r.name, l.name, l."displayOrder", r.rating,
         r."estimatedDeliveryMinutes", r."estimatedDeliveryMaxMinutes",
         r."operatingStatus", r."deliveryAvailability", r."imageKey", r."displayOrder"
ORDER BY l."displayOrder" NULLS LAST, r."displayOrder", r.id;

-- 2. Operating status summary
SELECT "operatingStatus",
       COUNT(*) AS restaurant_count
FROM "Restaurant"
GROUP BY "operatingStatus"
ORDER BY "operatingStatus";

-- 3. Missing or unmapped restaurant photo check (expect zero rows)
SELECT id, name, "imageKey"
FROM "Restaurant"
WHERE "imageKey" IS NULL
   OR BTRIM("imageKey") = ''
   OR "imageKey" NOT IN (
        'biryani', 'dosa', 'idli', 'paneer', 'pizza', 'pasta', 'burger', 'salad',
        'chicken-biryani', 'mutton-biryani', 'haleem', 'kebab',
        'noodles', 'meals', 'chaat', 'bakery', 'chai', 'dessert'
      )
ORDER BY id;
