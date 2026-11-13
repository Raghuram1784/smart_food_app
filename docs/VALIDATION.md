# Phase 1 validation

Date: 11 November 2026. Environment: Flutter 3.47.5, Dart 3.13.4, Windows; Pixel 8 emulator with Android 14 / API 34.

## Automated results

- `flutter pub get`: successful.
- `flutter analyze`: no issues found.
- `flutter test`: 11 tests passed.
- Search tests: case/whitespace normalization, multiword match, restaurant/cuisine matching, category intersection, under-₹250 filter, no-match case, catalog referential consistency.
- Persistence test: save dark appearance, destroy provider container, recreate it with stored preferences, verify dark selection restored.
- Nine widget interaction runs: 360, 393 and 430 logical pixels × System, Light, Dark. Home → restaurant → item sheet → back → Explore → empty search → reset → category selection → You → saved Dark appearance. No reported layout exceptions.
- Stock image contact sheet visually inspected: burger, pepperoni pizza, tomato penne, feta/olive salad all match their corresponding menu descriptions.

Early test failures were fixed before final verification: indefinite loading animations prevented test settling, and small-screen test actions needed explicit scrolling. Final run passed all 11 cases.

## Scope limitations

- Four dishes and three fictional restaurants; small, intentionally consistent Phase 1 catalog.
- Stock photos illustrate dishes; restaurant hero images show signature dishes, not real premises.
- Photo source sizes: burger 1600×1067, pasta 1800×1201, pizza 1800×1350, salad 1800×2400. Some do not meet the preferred 1400 px minimum in both dimensions for square detail imagery; they are sharp landscape originals, not upscaled.
- Prices are sample item prices; tax, delivery fees, live coverage and ordering are not implemented.
- Appearance persists; neighbourhood selection is session-only.
- Final brand, launcher artwork, application ID and release signing remain provisional.

## Android build and visual review

- `flutter build apk --debug`: successful. APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- Installed and launched successfully on Pixel 8 Android 14 emulator.
- Dark appearance selected through the UI, app force-stopped and relaunched: dark appearance restored. Actual restart screenshot retained.
- Captured and visually inspected both appearances near 360 / 393 / 430 logical px by setting emulator density to 480 / 440 / 402 at 1080 physical px; original density 420 restored. Widget tests use exact requested logical widths.
- Inspected restaurant screen, profile settings, local search and photo crops. Real search for pasta returned the matching penne dish and Hearth & Crust kitchen.
- Screenshots are actual emulator captures. `appearance-preview.jpg` and `viewport-review.jpg` are resized contact sheets assembled from those captures.
- No critical navigation or overflow problems observed in tested flows. Device-wide accessibility audits and production release signing are outside this validation.

Screenshots: `docs/screenshots/`. Main previews: `appearance-preview.jpg`, `viewport-review.jpg`, `restaurant-dark.png`, `profile.png`, `explore-light.png`, `search-pasta.png`, `home-dark-restarted.png`.

## Refinement validation supersedes the original visual report

See [refinement/REPORT.md](refinement/REPORT.md) for the current 16-test result, new typography/photos, Android light/dark/System checks, screenshot inventory and remaining limitations. Original results above describe the pre-refinement build.
