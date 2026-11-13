-- Preserved menu IDs, photos and category associations.
SELECT m.id,m.name,r.name AS restaurant,c.name AS category,s.name AS section,m."basePricePaise",m."imageKey",m."isVegetarian"
FROM "MenuItem" m JOIN "Restaurant" r ON r.id=m."restaurantId" JOIN "Category" c ON c.id=m."categoryId" JOIN "MenuSection" s ON s.id=m."sectionId" ORDER BY m."displayOrder",m.id;
