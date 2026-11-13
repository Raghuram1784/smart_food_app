-- Service-area coverage per Hyderabad locality via Locality, DeliveryZone, and RestaurantDeliveryZone.

-- 1. Eligible restaurant count, available dish count, and price range per locality
SELECT l.id AS locality_id,
       l.name AS locality,
       COALESCE(dz."isActive", false) AS delivery_zone_active,
       COUNT(DISTINCT CASE WHEN r."operatingStatus" = 'OPEN' THEN r.id END) AS eligible_open_restaurants,
       COUNT(DISTINCT r.id) AS total_eligible_restaurants,
       COUNT(DISTINCT mi.id) AS available_dishes,
       MIN(mi."basePricePaise") AS cheapest_paise,
       MAX(mi."basePricePaise") AS priciest_paise,
       ROUND(MIN(mi."basePricePaise")::numeric / 100, 2) AS cheapest_rupees,
       ROUND(MAX(mi."basePricePaise")::numeric / 100, 2) AS priciest_rupees,
       ROUND(AVG(CASE WHEN r."operatingStatus" = 'OPEN' THEN rz."estimatedMinutes" END)::numeric, 1) AS avg_eta_minutes
FROM "Locality" l
LEFT JOIN "DeliveryZone" dz ON dz.id = l.id
LEFT JOIN "RestaurantDeliveryZone" rz ON rz."zoneId" = dz.id AND rz."isEligible" = true
LEFT JOIN "Restaurant" r ON r.id = rz."restaurantId"
LEFT JOIN "MenuItem" mi ON mi."restaurantId" = r.id
                       AND r."operatingStatus" = 'OPEN'
                       AND mi."availabilityStatus" = 'AVAILABLE'
GROUP BY l.id, l.name, dz."isActive", l."displayOrder"
ORDER BY l."displayOrder", l.id;

-- 2. Service-area isolation check: eligible delivery zone count per restaurant
--    (verifies restaurants cover configured nearby zones, not all 10 localities)
SELECT r.id AS restaurant_id,
       r.name AS restaurant,
       l.name AS home_locality,
       r."operatingStatus",
       COUNT(CASE WHEN rz."isEligible" THEN 1 END) AS eligible_zone_count,
       STRING_AGG(dz.name, ', ' ORDER BY dz.name) FILTER (WHERE rz."isEligible") AS serviceable_areas
FROM "Restaurant" r
LEFT JOIN "Locality" l ON l.id = r."localityId"
LEFT JOIN "RestaurantDeliveryZone" rz ON rz."restaurantId" = r.id
LEFT JOIN "DeliveryZone" dz ON dz.id = rz."zoneId"
GROUP BY r.id, r.name, l.name, r."operatingStatus", r."displayOrder"
ORDER BY r."displayOrder", r.id;

-- 3. Active localities missing eligible OPEN restaurants (expect zero rows after Phase 2.5 seed)
SELECT l.id, l.name
FROM "Locality" l
WHERE l."isActive" = true
  AND NOT EXISTS (
    SELECT 1
    FROM "RestaurantDeliveryZone" rz
    JOIN "Restaurant" r ON r.id = rz."restaurantId"
    WHERE rz."zoneId" = l.id
      AND rz."isEligible" = true
      AND r."operatingStatus" = 'OPEN'
  )
ORDER BY l."displayOrder", l.id;
