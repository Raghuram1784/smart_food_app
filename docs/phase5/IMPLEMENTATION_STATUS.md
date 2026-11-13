# Phase 5 — implemented and verified

2026-11-12. Baseline: Phase 4 source and status inspected; no Git metadata. Existing pricing validates catalog/options and applies fees once per quote. Reuse its selection validation and exact calculator for aggregated cart amounts; preserve discovery pricing behavior.

Plan: additive commerce schema; versioned customer cart/address APIs; persisted quote expectations; atomic idempotent order snapshots/events; protected owner inbox; Flutter vertical slice; focused tests, one regression sweep, Android demonstration.

No development database reset, catalog reseed, JWT changes, actual payment, restaurant actions or simulated delivery.

## Implemented so far

- Migration 202611120003_commerce applied to food_delivery_dev; additive Cart/CartItem/CartItemAddOn, CustomerAddress, CartQuote, Order/OrderItem/OrderItemAddOn/OrderEvent, enums, restrictive historical FKs, unique cart/customer and checkout keys, quantity/money/default-address constraints. Existing custom search indexes preserved.
- backend/src/modules/commerce: DTOs, transaction store, cart/address service, aggregate pricing, order service and protected controllers. PricingService.selection extracted for reuse; existing calculator unchanged. Auth strategy unchanged.
- lib/features/commerce: repository/providers, secure pending-checkout recovery, cart badge and screen, address CRUD/editor, checkout, history/detail, owner inbox and authentication gate. Integrated routes, customization Add to cart, login-return intent and account entry points. Updated obsolete no-order UI copy.
- docs/phase5/ORDER_FLOW.md describes contracts, transaction/idempotency policy and future integration boundaries.

## Executed checks

- Baseline backend build passed; commerce backend build passed and migration applied successfully.
- Focused real-PostgreSQL commerce tests: 8 passed (parent plus seven groups), including concurrent updates, simultaneous duplicate checkout, fees once, tax/discount rounding, stale/expired quotes, injected write-failure rollback, snapshots, ownership, cart switch and demo-checkout restrictions. Uses food_delivery_test only; isolated fixture cleanup.
- Flutter analyzer passed after resolving initial parser/style issues.
- Focused Flutter commerce tests: 10 passed; cart/customizations/quantity/remove/badge, light/dark 360px bill, switch confirmation, login-required, duplicate submit, stale quote, address validation, empty lists, logout isolation. Test-only route gate and lazy-scroll setup corrected before pass.

## Regression and Android results

- Prisma validation PASS; all four migrations applied. NestJS build PASS, backend unit tests 3 PASS, full backend E2E suite 34 PASS, full Flutter suite 59 PASS. One complete regression sweep executed; after minor lifecycle and currency-format fixes, focused commerce tests 10 PASS and analyzer PASS. Final formatting checked 47 files with no changes.
- Android customer-to-owner commerce flow PASS on Pixel_8: actual login, Madhapur, owned restaurant menu, variant/add-on selection, two cart lines, full Flutter state reconstruction with server cart restoration, quantity increment, address creation, exact server bill, real order placement, customer history, owner inbox, unrelated-owner access denial, dark mode, existing smart search/single-meal quote checks.
- Android test adapter initially assumed a flat menu instead of sections; corrected. A test tap missed the below-fold checkout button; settled scrolling corrected. These were test automation defects, not a bypass of UI or database checks. The final complete order flow passed.
- Live order: a923bb86-4fe1-47dc-bf83-edc1df97462f / FD-AA98F142DE6365012887, ₹1,192. Read-only PostgreSQL verification PASS: 2 × Chicken Dum Biryani with variant/add-on plus 1 × Mutton Zafrani Dum Biryani; UNPAID, DEMO_NO_PAYMENT, PENDING_RESTAURANT, one ORDER_CREATED event, no publication/status simulation, emptied cart. See database-verification.json and android-result.json. The real synthetic order remains for manual review.
- Catalog and auth verification PASS: 28 restaurants, 224 items, 10 localities, 16 categories, 25 cuisines, 89 variants, 10 add-ons; four demo accounts; owner still has only deccan-handi-gachi.
- Screenshot report export initially replaced the integration binding's screenshot metadata. Fixed by preserving metadata and excluding raw image data from the compact JSON report. A separate read-only Android evidence pass captures the existing order/inbox without creating another order.

## Handoff and Phase 5.1 UI Refinement

Phase 5.1 completion and premium commerce UI refinement completed and verified:

- **Android storage & normal APK installation resolved:** Built the clean x86-64 normal debug APK (`flutter build apk --debug --target-platform android-x64 --no-pub`, `110,251,548` bytes, without integration-test `--dart-define` credentials), installed onto `emulator-5554` (`adb install -r` -> `Success`, `1.0G` free / `81%` used on `/data`), and verified cold launch (`Status: ok`, `LaunchState: COLD`). NestJS backend continues running on port `5000` with `DEMO_AUTH_ENABLED=true` and `DEMO_CHECKOUT_ENABLED=true`.
- **Root-cause Material 3 surface & real-quote fixes:**
  - Configured `CardThemeData(color: scheme.surfaceContainer, surfaceTintColor: Colors.transparent, elevation: 0, ...)` in `lib/core/design.dart` to eliminate unintended pink light-mode and dark-maroon dark-mode `surfaceTint` casts across commerce and catalog cards.
  - Fixed a real backend integration bug in `lib/features/commerce/cart_screen.dart` where `quoteValid` previously checked `quote!['addressId'] == chosen['id']` (whereas `POST /cart/quote` in `CartPricingService` returns `cartVersion` and `address` snapshot, not a top-level `addressId`); Cart now tracks `_quotedAddressId` cleanly so auto-quoting and live server bill breakdown load reliably against the real backend.
- **Additive backend presentation enhancements (`backend/src/modules/commerce/`):**
  - `commerce.store.ts` & `cart.service.ts`: added `present(cart)` returning exact `BigInt`-computed `unitPricePaise` and `lineTotalPaise` per cart item plus `itemCount` and `merchandiseSubtotalPaise` while preserving all existing cart response fields.
  - `orders.service.ts`: added `pendingCount` (`PENDING_RESTAURANT` order count) to `GET /restaurants/:restaurantId/orders`.
- **Redesigned commerce UIs & new owner read-only detail view:**
  - `lib/features/catalog/catalog.dart`: extracted `Dish.photoKeyFor(...)` so Cart and Order item thumbnails share Phase 3.1's distinctive dish photography mapping.
  - `lib/features/commerce/commerce_widgets.dart`: added `shortOrderRef`, `formatOrderTime`, `paymentStatusLabel`, `OrderStatusBadge`, `PaymentTag`, `CopyOrderRefButton`, and refined `OrderBill`.
  - `lib/features/commerce/cart_screen.dart`: compact restaurant header with `Menu` link and `Clear cart`, food-first `_CartItemCard` (thumbnail, grouped option/add-ons, `₹... each`, bordered stepper, `Remove`, right-aligned line total), compact `_DeliveryAddressCard`, auto-quoted `Bill summary` / actionable error banner, sticky CTA footer safe down to `360dp`, and redesigned `CheckoutScreen`.
  - `lib/features/commerce/orders_screen.dart` & `lib/app.dart`: distinct `Your order has been recorded` confirmation experience, scannable customer order history & details, Culinary Noir restaurant owner inbox with `pendingCount` summary banner, and new read-only `OwnerOrderDetailScreen` (`/inbox/:id/orders/:orderId`) with zero customer PII and no Phase 7 controls.
- **Post-edit verification results:**
  - `dart format --output=none --set-exit-if-changed lib test integration_test test_driver`: formatted 47 files (`0` changed).
  - `flutter analyze`: `No issues found!`.
  - `flutter test`: `65` tests passed (`test/commerce_test.dart`: `16` tests passed across `360px`/`393px`/`430px` Light and Dark themes, missing-address/422 error states, confirmation, history/detail, and owner inbox/detail).
  - Backend: `npm test` `3` passed (`0` failed); `npm run test:e2e` `34` passed (`0` failed, including `8` in `test/commerce.e2e.test.ts`); `npm run db:verify` confirmed catalog integrity (`28` restaurants, `224` items, `16` categories, `25` cuisines, `109` sections, `13` zones).
  - Android E2E (`integration_test/commerce_test.dart` on `emulator-5554`): passed (`All tests passed.`), recording order `FD-BBF358824650162F8830` alongside preserved order `FD-AA98F142DE6365012887`.
  - Visually inspected all 9 screenshots saved in `docs/phase5/screenshots/` (prior baseline captures archived under `docs/phase5/screenshots/before/`): `01-cart-multiple-items-light.png`, `02-cart-selected-address-light.png`, `03-checkout-light.png`, `04-order-confirmation-light.png`, `05-customer-order-history-light.png`, `06-customer-order-details-light.png`, `07-owner-inbox-dark.png`, `08-owner-order-detail-dark.png`, and `09-cart-dark.png`.

Manual flow: sign in as customer@demo.test, open a meal and Add to cart; use Your cart, save/select an address, Review order, and Confirm order. Your orders includes the recorded orders (`FD-BBF358824650162F8830` and `FD-AA98F142DE6365012887`). Sign in as restaurant@demo.test and open Deccan Handi & Dum · Incoming orders to inspect incoming records and tap View details. Demo passwords remain locally configured as requested; do not commit environment files or private test artifacts. Next development phase is Phase 6 payment integration per ORDER_FLOW.md; do not rebuild Phase 5.

## Known limits

No real payment, restaurant action, dispatch, Socket.IO or route/geocode verification. No stock inventory/reservations are claimed; catalog availability is revalidated at checkout. Cart restoration is tested across full Flutter state reconstruction, not OS process death. iOS/web not tested. History uses bounded offset pagination. Address edits use full replacement DTOs; address records have no optimistic edit version. Cart promotions are supported by the API but no dedicated cart promotion-entry UI is included. Session limiter and event publication/retention remain local-phase infrastructure constraints described in prior docs and ORDER_FLOW.md. Existing Prisma/pg concurrent-query deprecation warnings are non-failing under installed pg 8. No repository push/commit (workspace has no Git metadata).

## Main files changed

backend/prisma/schema.prisma; migrations/202611120003_commerce/migration.sql; src/modules/commerce/*; pricing/pricing.service.ts; app.module.ts; main.ts; .env.example; package.json; scripts/verify-orders.ts and auth-test-defines.ts; test/commerce.e2e.test.ts. Flutter: lib/features/commerce/*, app.dart, auth login/account entry, quote_panel.dart, restaurant/profile copy. Tests/evidence: test/commerce_test.dart, integration_test/commerce_test.dart, integration_test/order_evidence_test.dart, test_driver/commerce.dart, docs/phase5/*. Existing pricing calculator and opaque authentication protocol preserved.
