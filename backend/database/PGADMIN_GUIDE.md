# Inspect the local catalog

Open the PostgreSQL server registered for `localhost:5432` in pgAdmin 4. This machine's port 5432 currently runs PostgreSQL 15.10; the separately installed PostgreSQL 18 service is not this project's server. Select **Databases → food_delivery_dev**, then **Tools → Query Tool**. Use your local login or `food_app_user`; passwords remain in your private local configuration.

Tables and relationships are already created by Prisma. Do not create or alter them manually.

Open and execute the SQL files under `verify/` in order:

1. `01_tables.sql`: 12 catalog tables plus `_prisma_migrations`, constraints and indexes.
2. `02_restaurants.sql`: 4 fictional kitchens with original IDs and illustrative estimates.
3. `03_menu_items.sql`: 8 dishes, correct kitchen/category/section, integer paise and image keys.
4. `04_relationships.sql`: restaurant menu counts and cuisine links; orphan query returns zero rows.
5. `05_availability.sql`: explicit availability, no invented stock or delivery coverage.
6. `06_prices.sql`: prices in paise and decimal rupee presentation; negative-price query returns zero rows.
7. `07_catalog_summary.sql`: counts and categories; duplicate-ID query returns zero rows.

Expected baseline: restaurants 4, menu items 8, categories 8, cuisines 6, menu sections 7, delivery zones 3. Variants, add-ons, fee rules and restaurant-zone eligibility have no invented seed records. Counts can legitimately grow after development. Missing baseline IDs indicate incomplete seed or intentional later edits; duplicate IDs are prevented by primary keys.

For a new machine only: run `01_create_role.sql` on `postgres`, set a newly created role's password through pgAdmin's role properties, and use `02_create_database.sql` to generate the missing database creation statement. Execute that returned statement separately with auto-commit enabled. Then run `03_permissions.sql` on `food_delivery_dev` and `04_verify_setup.sql`. Existing credentials are never reset. Run the backend migration and seed commands; no manual table setup is needed.

## Phase 2.5 Hyderabad Expansion Verification

After running `npx prisma migrate deploy` and `npm run db:seed:hyd`, use these additional scripts in `verify/` in order:

8. `08_localities.sql`: Total localities (10 Hyderabad neighbourhoods), based-in restaurant counts, and the `RestaurantDeliveryZone` service-area matrix.
9. `09_hyderabad_restaurants.sql`: All 28 restaurants with home locality, `operatingStatus`, serviceable zone count, menu item count, and missing photo check (0 rows expected).
10. `10_hyderabad_menu.sql`: All 213+ menu items with vegetarian flag, integer paise and decimal rupee price, category/cuisine breakdowns, and explicit availability (`AVAILABLE` / `SOLD_OUT` / `UNAVAILABLE` with `availabilityReason`, e.g., seasonal Haleem).
11. `11_catalog_diversity.sql`: Summary totals (restaurants, menu items, categories, localities, cuisines, variants, add-ons), duplicate identifier checks (0 rows expected), price validity check (`<= 0` paise check, 0 rows expected), and distinct `imageKey` audit across `MenuItem` and `Category` (including veg/meat photo mismatch check).
12. `12_area_coverage.sql`: Service-area coverage per locality (`Locality` + `DeliveryZone` + `RestaurantDeliveryZone` eligible restaurant count, available dish count, min/max prices, average ETA) and per-restaurant delivery zone isolation check.

Expected baseline after Phase 2.5 seed:
- Localities: 10 (Hyderabad neighbourhoods, including `Kukatpally / KPHB`)
- Delivery zones: 10 active Hyderabad zones (legacy Bengaluru zones marked `isActive = false`)
- Restaurants: 28 (4 original demo kitchens + 24 Hyderabad kitchens)
- Menu items: 213+ (8 original + 205+ Hyderabad dishes, including variants & add-ons)
- Categories: 16 (preserving the 8 original IDs plus 8 expanded categories)
- Cuisines: 10+
- Valid image keys: 18 across `MenuItem`, `Category`, and `Restaurant`

