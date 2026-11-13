-- Fictional restaurants: ratings/times are illustrative, not operational measurements.
SELECT id, name, slug, rating, "reviewCount", "estimatedDeliveryMinutes", "estimatedDeliveryMaxMinutes", "operatingStatus", "deliveryAvailability", "isDemo", "imageKey" FROM "Restaurant" ORDER BY "displayOrder",id;
