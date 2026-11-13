-- Hyderabad localities, based-in restaurant counts, and RestaurantDeliveryZone service-area matrix.

-- 1. Total localities summary
SELECT COUNT(*) AS total_localities,
       COUNT(CASE WHEN "isActive" THEN 1 END) AS active_localities
FROM "Locality";

-- 2. Service area configuration
SELECT id, name, city, "displayOrder", "isActive"
FROM "Locality"
ORDER BY "displayOrder", id;

-- 3. Restaurants physically located in each locality
SELECT l.id,
       l.name AS locality,
       COUNT(r.id) AS restaurant_count,
       COUNT(CASE WHEN r."operatingStatus" = 'OPEN' THEN 1 END) AS open_restaurants
FROM "Locality" l
LEFT JOIN "Restaurant" r ON r."localityId" = l.id
GROUP BY l.id, l.name, l."displayOrder"
ORDER BY l."displayOrder", l.id;

-- 4. Delivery zone summary and RestaurantDeliveryZone service-area matrix
SELECT dz.id AS zone_id,
       dz.name AS zone_name,
       dz."isActive",
       dz."isIllustrative",
       COUNT(CASE WHEN rz."isEligible" THEN 1 END) AS eligible_restaurants
FROM "DeliveryZone" dz
LEFT JOIN "RestaurantDeliveryZone" rz ON rz."zoneId" = dz.id
GROUP BY dz.id, dz.name, dz."isActive", dz."isIllustrative"
ORDER BY dz."isActive" DESC, dz.name;

SELECT r.id AS restaurant_id,
       r.name AS restaurant,
       l.name AS home_locality,
       dz.id AS zone_id,
       dz.name AS delivery_zone,
       rz."isEligible",
       rz."estimatedMinutes"
FROM "RestaurantDeliveryZone" rz
JOIN "Restaurant" r ON r.id = rz."restaurantId"
LEFT JOIN "Locality" l ON l.id = r."localityId"
JOIN "DeliveryZone" dz ON dz.id = rz."zoneId"
ORDER BY r."displayOrder", r.id, dz.name;
