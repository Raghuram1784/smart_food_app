# Phase 3 implementation status

Updated 2026-11-12 (Asia/Calcutta). Phase 3 source changes are paused until Phase 2.5 verification finishes.

## Objective
Database-driven smart discovery, server-authoritative exact pricing, payable-budget filters, explainable ranking, comparison and customization. Preserve themes/assets/navigation; improve motion with reduced-motion support. No auth/cart/orders/payments/live-order simulation.

## Synchronization audit
Active path: `C:/Users/Raghu Ram/Desktop/Smart_Food_App`. This same folder already contains Antigravity's Phase 2.5 work: `backend/prisma/catalog_hyd.json`, `localities.json`, `seed_hyd.ts`, migration `202611120001_add_locality`, area API/module, Flutter locality selection, integration test/driver and `docs/phase2_5/screenshots/`.

The initial claim of an old four-restaurant workspace came from stale conversation context and was corrected after reading actual files/database. Do not generate another catalog. Desktop search found no separate Hyderabad checkout; no separate Antigravity path was supplied. This folder has no `.git`, so Git status reports “not a git repository”; there are no branches/commits to merge. Codex attached-artifact inventory contains no worktrees. No files were copied from another checkout, no database reset performed, no development seed rerun. Existing work remains in place.

Actual development database read: 28 restaurants, 224 items, 10 localities, 16 categories, 25 cuisines, 89 variants, 10 add-ons, 0 pricing rules. There are 13 DeliveryZone records (10 Hyderabad plus three legacy illustrative zones), distinct from the 10 Locality records. Migration status: both `202611110001_catalog` and `202611120001_add_locality` applied, schema up to date.

## Baseline checks
- Nest build: PASS.
- Backend unit tests: 3 PASS.
- Dedicated food_delivery_test integration suite: 9 PASS including locality filtering, availability and actual database refusal; test guard prevents development mutations. Seed runs occurred only inside that isolated test database.
- Flutter analyze: no issues.
- Flutter tests: 26 PASS.
- Live API check initially refused connection: API process was not running. Restart underway.
- Android baseline attempt could not run: emulator was stopped. Existing AVD lookup underway; no app assertion failure observed.
- Existing pg driver emits a deprecation warning from Prisma's query scheduling; current tests pass. No dependency upgrade to Prisma 8 release candidate.

## Planned changes after verification
Pricing module (DTOs/service/calculator/contracts), catalog smart search extension, explicit illustrative pricing config/migration as needed, isolated pricing/search tests, Flutter discovery filters/ranking/comparison/quote customization, shared motion helpers/router transitions, updated docs and Android evidence.

## Next step
Start the existing API and emulator; verify real API area filtering and the current Hyderabad Android integration. Document synchronization as complete before starting pricing implementation. No Phase 3 business code or migrations written yet.

Live API synchronization checks: HTTP 200; Madhapur 18 kitchens, Gachibowli 11, Secunderabad 4, every returned kitchen includes the requested service-area relationship. API restarted without data mutation. Pixel_8 emulator restarted; Android test running. Baseline source hashes saved in BASELINE_SHA256.json (no secrets).

## Android baseline troubleshooting
Build initially failed inside Java NIO before app compilation: `UnixDomainSockets.connect0` / `Unable to establish loopback connection`. IPv4 and java.io.tmpdir alone did not resolve it. Current retry uses the documented Windows socket-specific property `jdk.net.unixdomain.tmpdir` pointing to `build/jtmp`; Java's Windows TEMP search order takes precedence over java.io.tmpdir. Reference: https://docs.oracle.com/en/java/javase/21/core/java-networking.html . This is a host runtime issue, not evidence of an app regression.

## Intended Phase 3 file groups
- `backend/src/modules/pricing/`: validated quote input, exact bigint calculator, read-only snapshot service, contracts/controller/module.
- `backend/src/modules/catalog/`: reuse item includes/search; add strict smart discovery endpoint, combined filters, deterministic ranking/explanations and comparison.
- `backend/prisma/seed_pricing.ts`: idempotent illustrative fee configuration only; never regenerate catalog.
- `backend/test/`: isolated pricing boundary/availability/customization/ranking tests with fixed IDs and restoration.
- `lib/features/discovery/`: filter sheet, budget/sort controls, server-generated results and comparison.
- `lib/features/pricing/`: typed quote repository, option selection, server breakdown and re-quote.
- `lib/core/motion.dart`, router and sheets: restrained fade/slide/size transitions, reduced-motion handling.
- `docs/phase3/`, integration tests: rules/quote policy, tests, screenshots and handoff.

## Synchronization complete — Phase 3 resumed
Existing Hyderabad Android integration PASS (app + driver). Socket-specific temporary-directory setting fixed the host issue. All expected source/database records verified; no synchronization copy needed. See SYNCHRONIZATION.md. Now implementing authoritative pricing and strict smart discovery against the verified 28/224 catalog.

## Phase 3 completion (2026-11-12)

### What Codex implemented before interruption
- **Backend pricing engine**: `backend/src/modules/pricing/pricing.dto.ts` (`QuoteInput`, `CompareInput`), `pricing.calculator.ts` (`PRICING_POLICY = 'single-meal-v1'`, `QUOTE_TTL_MS = 120_000`, integer `bigint` exact paise math and `HALF_UP` rounding), `pricing.service.ts` (read-only transactional quote/compare), `pricing.module.ts`, and `backend/prisma/seed_pricing.ts`.
- **Backend smart search**: `backend/src/modules/catalog/smart-query.dto.ts` (`SmartQuery` via `OmitType(CatalogQuery, ['area'] as const)` requiring `area`, plus budget/diet/time/rating/restaurant/sort filters), `smart-search.service.ts`, shared mapper/SQL helpers (`catalog.mapper.ts`, `catalog.service.ts`, `catalog.controller.ts`), and `PricingModule` registration in `AppModule`.
- **Flutter Phase 3 UI & motion**: `lib/core/motion.dart` (reduced-motion-aware `Motion`, `Reveal`, `buildMotionPage`, `showMotionSheet`), `lib/features/pricing/pricing_repository.dart` (`MealQuote`, `PricingRepository`, `pricingQuoteProvider`), `lib/features/pricing/quote_panel.dart` (`PriceBreakdown`, customization chips, quantity controls), `lib/features/discovery/smart_filters.dart`, and `lib/features/discovery/smart_search_screen.dart`.
- **Initial tests**: `backend/test/pricing.e2e.test.ts`, `test/smart_discovery_test.dart`, `integration_test/smart_discovery_test.dart`, and `test_driver/smart_discovery.dart`.

### What Antigravity completed and fixed
- **Quote expiry isolation**: Updated `backend/src/modules/pricing/pricing.service.ts` so `expiresAt` uses only the chosen rules (`chosen.filter((r) => r.effectiveUntil)`) instead of all fetched active rules.
- **Deterministic tie-breaking**: Updated `backend/src/modules/catalog/smart-search.service.ts` to pass `'en'` locale in `localeCompare(b.quote.item.id, 'en')`.
- **Issue A & Issue B test coverage**: Expanded `backend/test/unit.test.ts` (required `area` on smart/pricing DTOs vs optional `area` on legacy `CatalogQuery`) and `backend/test/pricing.e2e.test.ts` (cross-item variant/add-on `422` rejection, inactive Bengaluru `indiranagar` zone `422`, missing `area` `400`, legacy `200`, seasonal `haleem` `total: 0`, strict `18400`-paise Masala Dosa boundary, fail-closed missing `DEMO_PLATFORM_V1` `422`, unrelated-rule expiry isolation, and `RepeatableRead` concurrency check).
- **Flutter completion**: Added `ruleCodes` parsing + `unavailableMatches` / `unavailableCatalogProvider` in `lib/features/pricing/pricing_repository.dart`; rendered server `400`/`404`/`422` `error.message` and `Applied rules: ...` in `lib/features/pricing/quote_panel.dart`; formatted pre-filled budget via `formatPaise` in `lib/features/discovery/smart_filters.dart`; rendered non-orderable catalog matches under `'Unavailable in catalog (not orderable)'` inside `'Nothing fits just yet.'` in `lib/features/discovery/smart_search_screen.dart`; added non-available ordering/quote notice in `lib/shared/components.dart`; expanded `test/smart_discovery_test.dart`; updated `integration_test/smart_discovery_test.dart` for `Old City Mutton Haleem`.

### Files modified in Phase 3
- **Backend**: `backend/prisma/seed_pricing.ts`, `backend/src/app.module.ts`, `backend/src/main.ts`, `backend/src/modules/catalog/catalog-query.dto.ts`, `backend/src/modules/catalog/catalog.controller.ts`, `backend/src/modules/catalog/catalog.mapper.ts`, `backend/src/modules/catalog/catalog.module.ts`, `backend/src/modules/catalog/catalog.service.ts`, `backend/src/modules/catalog/smart-query.dto.ts`, `backend/src/modules/catalog/smart-search.service.ts`, `backend/src/modules/pricing/pricing.calculator.ts`, `backend/src/modules/pricing/pricing.dto.ts`, `backend/src/modules/pricing/pricing.module.ts`, `backend/src/modules/pricing/pricing.service.ts`, `backend/package.json`.
- **Flutter**: `lib/app.dart`, `lib/core/motion.dart`, `lib/features/catalog/catalog.dart`, `lib/features/discovery/smart_filters.dart`, `lib/features/discovery/smart_search_screen.dart`, `lib/features/pricing/pricing_repository.dart`, `lib/features/pricing/quote_panel.dart`, `lib/shared/components.dart`.
- **Tests & Docs**: `backend/test/unit.test.ts`, `backend/test/pricing.e2e.test.ts`, `test/smart_discovery_test.dart`, `test/fixtures/smart_page.json`, `integration_test/smart_discovery_test.dart`, `test_driver/smart_discovery.dart`, `docs/phase3/IMPLEMENTATION_STATUS.md`, `docs/phase3/SYNCHRONIZATION.md`, `docs/phase3/BASELINE_SHA256.json`, `docs/phase3/screenshots/`.

### Backend endpoints & Pricing rules
- `GET /api/v1/catalog/smart-search` (requires valid `area`, strict `maxPayablePaise`, diet/time/rating/restaurant filters, `value|price|time|rating|relevance` sorting).
- `POST /api/v1/pricing/quote` (authoritative single-meal final payable calculation across integer paise base, variant, add-ons, quantity, and active fee rules).
- `POST /api/v1/pricing/compare` (reuses identical pricing calculation engine across 2–3 unique menu items).
- Legacy Phase 2/2.5 endpoints (`GET /api/v1/catalog/restaurants`, `GET /api/v1/catalog/restaurants/:id`, `GET /api/v1/catalog/search`, `GET /api/v1/catalog/areas`, `GET /api/v1/health`) remain intact.
- **Database & Pricing rules**: Existing schema (`202611110001_catalog`, `202611120001_add_locality`) reused with zero new migrations. `food_delivery_dev` remains intact (`28` restaurants, `224` items, `10` localities, `16` categories, `25` cuisines, `89` variants, `10` add-ons, `13` delivery zones, `109` sections, `116` item-addons, `55` restaurant-cuisines, `111` restaurant-delivery-zones) plus 3 active illustrative fee rules (`DEMO_PACKAGING_V1`: `1000` paise, `DEMO_DELIVERY_V1`: `2000` paise, `DEMO_PLATFORM_V1`: `500` paise; all `HALF_UP`, `isActive: true`).

### Verification & Android evidence
- **Backend build & tests**: `npm run build` PASS; `npm test` PASS (`3/3`); `npm run test:e2e` PASS (`19/19` on `food_delivery_test`).
- **Flutter checks**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` PASS (`28 files (0 changed)`); `flutter analyze` PASS (`No issues found!`); `flutter test` PASS (`37/37`).
- **Android end-to-end (`emulator-5554`, `http://10.0.2.2:5000/api/v1`)**: `flutter drive --driver=test_driver/smart_discovery.dart --target=integration_test/smart_discovery_test.dart -d emulator-5554 --no-pub` PASS (`All tests passed!`).
- **Captured screenshots (`docs/phase3/screenshots/`)**: `01-madhapur-150-honest-empty.png`, `02-eligible-server-priced-meals.png`, `03-customized-live-quote.png`, `04-live-comparison.png`, `05-seasonal-not-orderable.png`, `06-smart-discovery-dark.png`.

### Remaining limitations & Next steps
- Demo catalog/pricing scope only: pricing rules use illustrative `DEMO_*_V1` fixed fees (`₹10` + `₹20` + `₹5`), restaurant ratings and ETAs are illustrative estimates, and offline catalog items do not compute client-side final-payable totals.
- Phase 3 intentionally stops before authentication, cart/checkout/orders, Razorpay/payments, live tracking, AI Order Rescue, and web storefront.
- **Next development steps**: Begin Phase 4 design for authenticated customer sessions, persisted cart/order creation binding to verified server quote snapshots, and downstream payment/order lifecycle integration.

## Phase 3.1 UX Refinement completion (2026-11-12)

### What changed in Phase 3.1
- **Compact food-first search cards (`lib/features/discovery/smart_meal_card.dart`, `smart_search_screen.dart`)**: Replaced tall single-column text-heavy cards with compact cards featuring dish photography, restaurant attribution, inline `final · min · rating` summary, customer-friendly savings/preference copy (`buildCustomerExplanation`), and a single `Wrap` CTA bar (`View meal & quote`, `Compare`, `Menu`). Removed user-facing `Value score`, raw `paise`, internal weight percentages, and `page N` labels from the main feed.
- **Five distinct honest empty states (`lib/features/discovery/smart_empty_state.dart`, `lib/features/pricing/pricing_repository.dart`)**: Added `PricingRepository.diagnoseEmpty()` (`EmptyReason`: `seasonalOrUnavailable`, `noKitchensInLocality`, `exceedsBudget`, `exceedsTime`, `noMatchingDishes`) backed by live catalog/search queries, giving actionable recovery buttons (`Increase budget to ₹...`, `View alternatives above ₹...`, `Remove time limit`, `Change locality`, `Browse available meals`, `Reset filters`/`Reset search`).
- **Pricing bottom sheet refinement (`lib/shared/components.dart`, `lib/features/pricing/quote_panel.dart`)**: Moved item/comparison sheets onto the root navigator (`useRootNavigator: true`) so the bottom navigation bar stays covered; streamlined `PriceBreakdown` inside `Material(surfaceContainer)` with selection summary, conditional customization/discount/tax rows, prominent `Final payable`, inline `Refresh quote`, and a collapsed `Quote & fee details` expansion tile for internal `DEMO_*_V1` rule transparency.
- **Side-by-side meal comparison (`lib/features/discovery/meal_comparison_sheet.dart`)**: Replaced vertical stacked breakdown lists with a compact 2–3 column `_ComparisonMatrix` comparing photo, standout badge (`Lowest total`, `Fastest`, `Best balance`), restaurant, final payable, delivery estimate, sample rating, availability, subtotal + fees, distinction copy (`saves ₹...` / `faster estimate`), and direct `Inspect` navigation.
- **Filter sheet & incremental pagination (`lib/features/discovery/smart_filters.dart`, `smart_search_screen.dart`)**: Added header `Clear filters` (preserving selected locality), budget preset chips, delivery-time and rating `ChoiceChip` rows, filter count badge on the toolbar button, horizontal filter/category strip, compact `labelLarge` sort selector, and `Showing X of Y meals` + `Show more meals (... remaining)` incremental pagination.
- **Expanded food photo mapping (`assets/images/food/`, `lib/features/catalog/catalog.dart`)**: Added 6 distinct editorial food assets (`karam-dosa.jpg`, `uttapam.jpg`, `vada.jpg`, `dal-curry.jpg`, `roti-naan.jpg`, `cold-beverage.jpg`) and `Dish.photoKey` so `karam`/`pesarattu`/roast variants, uttapams, vadas/punugulu/bajji, dals/curries, naans/rotis, and cold drinks render distinct photos without modifying PostgreSQL `MenuItem.imageKey` values.

### Verification & Screenshots (Phase 3.1)
- **Before vs After screenshots (`emulator-5554`)**: Original Phase 3 captures preserved in `docs/phase3/screenshots/before/`; refined Phase 3.1 captures verified in `docs/phase3/screenshots/` (`01-madhapur-150-honest-empty.png` through `06-smart-discovery-dark.png`).
- **Backend regression suite**: `npm test` PASS (`3/3`) and `npm run test:e2e` PASS (`19/19`).
- **Flutter checks**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` PASS (`31 files`); `flutter analyze` PASS (`No issues found!`); `flutter test` PASS (`41/41`).
- **Android end-to-end (`emulator-5554`)**: `flutter drive --driver=test_driver/smart_discovery.dart --target=integration_test/smart_discovery_test.dart -d emulator-5554 --no-pub` PASS (`All tests passed!`).
