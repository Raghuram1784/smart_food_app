-- Grouped restaurant menus; counts are 4,2,1,1 for tiffin,hearth,table,bun.
SELECT r.id,r.name,count(m.id) AS menu_count FROM "Restaurant" r LEFT JOIN "MenuItem" m ON m."restaurantId"=r.id GROUP BY r.id ORDER BY r."displayOrder";
SELECT r.name AS restaurant,c.name AS cuisine FROM "RestaurantCuisine" rc JOIN "Restaurant" r ON r.id=rc."restaurantId" JOIN "Cuisine" c ON c.id=rc."cuisineId" ORDER BY r.name,c.name;
-- Must return zero orphaned/incorrect-section records.
SELECT m.id FROM "MenuItem" m LEFT JOIN "Restaurant" r ON r.id=m."restaurantId" LEFT JOIN "Category" c ON c.id=m."categoryId" LEFT JOIN "MenuSection" s ON s.id=m."sectionId" AND s."restaurantId"=m."restaurantId" WHERE r.id IS NULL OR c.id IS NULL OR s.id IS NULL;
