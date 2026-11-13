-- Fresh seed: 4 restaurants, 8 items, 8 categories, 6 cuisines, 7 sections, 3 illustrative zones.
SELECT 'Restaurant' AS entity,count(*) AS records FROM "Restaurant"
UNION ALL SELECT 'MenuItem',count(*) FROM "MenuItem"
UNION ALL SELECT 'Category',count(*) FROM "Category"
UNION ALL SELECT 'Cuisine',count(*) FROM "Cuisine"
UNION ALL SELECT 'MenuSection',count(*) FROM "MenuSection"
UNION ALL SELECT 'DeliveryZone',count(*) FROM "DeliveryZone"
UNION ALL SELECT 'MenuItemVariant',count(*) FROM "MenuItemVariant"
UNION ALL SELECT 'AddOn',count(*) FROM "AddOn"
UNION ALL SELECT 'PricingRule',count(*) FROM "PricingRule";
SELECT id,count(*) FROM "MenuItem" GROUP BY id HAVING count(*)>1; -- Expect zero.
SELECT id,name,"imageKey","isActive" FROM "Category" ORDER BY "displayOrder";
