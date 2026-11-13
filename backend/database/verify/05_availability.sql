-- Status is explicit; no inventory quantity or real rider movement is claimed.
SELECT id,name,"availabilityStatus","availabilityReason","availabilityUpdatedAt",version FROM "MenuItem" ORDER BY "displayOrder";
SELECT id,"menuItemId",name,"isAvailable","availabilityReason","availabilityUpdatedAt" FROM "MenuItemVariant";
SELECT z.name,z."isIllustrative",rz."restaurantId",rz."isEligible" FROM "DeliveryZone" z LEFT JOIN "RestaurantDeliveryZone" rz ON rz."zoneId"=z.id ORDER BY z.name;
-- NULL associations mean no delivery eligibility has been established.
