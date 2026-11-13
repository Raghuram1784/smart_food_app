# Catalog API contract v1

All data comes from PostgreSQL. Bundled photo assets are resolved only by Flutter; database values contain portable image keys, never Windows paths. Later media may add optional `imageUrl` (HTTPS) alongside imageKey without breaking current clients.

Success envelope: `{ "data": <object-or-array>, "requestId": "uuid" }`; the same ID appears in `x-request-id`. Errors use `{ "error": { "code": "INVALID_REQUEST|NOT_FOUND|SERVICE_UNAVAILABLE|REQUEST_FAILED", "message": "safe text or validation messages" }, "requestId": "uuid" }`. Clients must ignore additive fields.

Restaurant fields include id, slug, name, description, imageKey, cuisineDescription, cuisines[{id,name}], rating (JSON number), reviewCount (nullable), estimatedDeliveryMinutes/estimatedDeliveryMaxMinutes, operatingStatus, deliveryAvailability, isDemo and startingPricePaise (nullable). Unknown location coordinates and review counts stay null. A sample rating is never presented as verified customer feedback.

MenuItem includes id, restaurantId, categoryId, sectionId, name, description, imageKey, basePricePaise, isVegetarian, availabilityStatus, availabilityReason, availabilityUpdatedAt, version, category, section, restaurant, variants and addOns. Availability enum is AVAILABLE/SOLD_OUT/UNAVAILABLE. There is no inferred stock quantity. A menu returns `{restaurant,sections:[{id,name,displayOrder,items:[...]}]}` in section/display order.

Categories return id/name/slug/imageKey/displayOrder/isActive. List/search page data is `{items,total,page,limit}`; deterministic order is displayOrder then ID. Queries normalize surrounding/repeated whitespace. Search ANDs words; each word can match dish name/description/category or restaurant name/cuisine. Category and cuisine use stable IDs. SQL filtering and count occur in the database. Literal punctuation is data, not executable SQL. Offset pagination is appropriate here; future large catalogs should add opaque seek cursors. Menus intentionally return a complete single restaurant menu; add pagination before very large operator catalogs.

Paise is authoritative: 14900 = ₹149, 14937 = ₹149.37. Flutter uses integer quotient/remainder to format prices. No floating-point billing or hidden fees. Options exist structurally but are empty in the preserved seed because original catalog has none.
