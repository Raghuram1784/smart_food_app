# Phase 1 visual refinement

## Audit and scope

Inspected the live workspace, README, pubspec, all existing screens, shared components, design definitions, preferences/router code, tests, font files and photo mappings before editing. No AGENTS.md was present. Baseline `flutter test`: 11 passed. Captured the running Android app before changes under `before/`; older Phase 1 captures remain in `docs/screenshots/`.

The repository had Home, Search, Restaurant, item sheets and Profile/Appearance. No cart or favorites implementation existed. Retained Flutter project/native configuration, dependencies, Riverpod providers, go_router routes, SharedPreferences key/storage and search/filter implementation. No preferences were cleared. No Phase 2 systems added.

## Before → after

| Area | Before | Refinement |
|---|---|---|
| Typography | Large Fraunces serif greetings and Manrope UI | Bricolage Grotesque editorial hierarchy + Sora functional text, deliberate weights/line heights |
| Home | Pizza-first feature, categories below hero | Indian food feature; categories before hero; clearer header/search; distinct peach, pistachio and sea-glass collections |
| Light | Predominantly beige surfaces | Warm paper background, terracotta actions, selective colorful supporting surfaces and fine borders |
| Dark | Flat charcoal and brown accents | Layered charcoal, burnt-clay feature, forest collection, teal information surfaces and copper actions |
| Listings | Photo/name/cuisine | Bordered card, separate rating badge, clear delivery estimate and sample starting price |
| Menu | Small photos, restaurant label repeated | Larger square food crops, two-line ingredient preview, clear item price and detail affordance |
| Detail sheet | Fixed-height crop and serif item name | Responsive aspect-ratio photo, kitchen label, Sora item title/price, quieter sample-price explanation |
| Image handling | Full source decode | Device-aware bounded decode widths, separate focal crops, compact error semantics |

Both themes still share all geometry, content, photos, active fonts and interactions. The single existing ThemeData/ColorScheme architecture now has a CulinaryColors extension for supporting surfaces.

## Typography decision

Recommend Bricolage Grotesque + Sora. On actual Android screens its expressive sans-serif headings feel more contemporary and cohesive with the functional UI, while retaining a distinct greeting/section hierarchy. Fraunces + Sora is legible but retains the earlier formal editorial character. Both versions were built, installed and captured: `fraunces-sora.png`, `bricolage-sora.png`. The comparison capture includes an intervening category spacing fix, so it is a visual comparison rather than a pixel-identical font-only experiment.

Default active families: exactly two. Fraunces is retained only as a build-time comparison option. Fonts are actual locally bundled TTF files; licences are bundled and visible through the existing licence screen. Text scaling is preserved; no clamping is used.

## Photography and catalog

See [ASSETS.md](ASSETS.md) for URLs, creators, source dimensions, derivatives, licences and the resolved failed candidate. Four new accurately labelled Indian dishes join one fictional kitchen: masala dosa, vegetable idli, vegetable biryani, paneer pepper masala. This additive content change meets the Indian cuisine direction without replacing the original dishes or changing the data models. The four original IDs and prices are tested. One burger ingredient description was corrected to mention visible bacon.

Home hero: original pizza feature replaced by dosa; the original Hearth & Crust feature remains lower on the home page. Existing pizza, pasta, burger and salad assets stay assigned to their original dishes. No fake ordering controls or unrelated placeholder photos were added.

## Files changed / added

- `lib/core/design.dart`: central typography, shared semantic colors, supporting ThemeExtension, control styles.
- `lib/main.dart`: current font licence registration.
- `lib/shared/components.dart`: photo decoding/fallbacks, restaurant cards, food rows and item sheets.
- `lib/features/discovery/home_screen.dart`: refined home composition, preserved location selection.
- `lib/features/discovery/home_widgets.dart` (new): category strip and editorial feature.
- `lib/features/restaurant/restaurant_screen.dart`: hero scale and functional title typography.
- `lib/features/profile/profile_screen.dart`: appearance selection surface.
- `lib/features/catalog/catalog.dart`: additive Indian kitchen/dishes/categories; ingredient correction.
- `pubspec.yaml`: font registration and licence assets; dependency versions unchanged.
- `test/widget_test.dart`: retained navigation coverage adapted for moved collection and larger catalog.
- `test/refinement_test.dart` (new): original-price preservation, Indian search, asset decode, contrast and text-scaling checks.
- `assets/fonts/`: Bricolage Grotesque/Sora TTF and SIL OFL files.
- `assets/images/{food,categories,restaurants,hero}/`: optimized Indian food derivatives.
- `tool/refine_assets.py`, `tool/fetch_assets.ps1`: reproducible licensed download/crop pipeline.
- README, credits, this report and actual Android screenshots.

Navigation and business-logic source files `lib/app.dart` and `lib/core/providers.dart` were not rewritten.

## Final validation — 11 November 2026

- Baseline: 11 tests passed before edits.
- Final `flutter pub get`: succeeded; dependencies preserved.
- `dart format lib test`: completed.
- Final `flutter analyze`: no issues found.
- Final `flutter test`: **16 passed**. Covers retained search/filter/navigation/persistence flows across exact 360/393/430 logical widths and System/Light/Dark, original IDs/prices, Indian search mappings, all catalog image decodes, semantic contrast, and 200% text scaling at 360px in both themes.
- `flutter build apk --debug`: succeeded; installed and launched on Pixel 8 / Android 14 emulator. APK at `build/app/outputs/flutter-apk/app-debug.apk`.
- Actual Android checks: both font candidates rendered; home, listings, menu and dish sheets captured in Light and Dark; settings and System-following-OS behavior captured. Selecting System followed OS dark and light changes. OS appearance restored to its original light setting. Saved Light mode survived restart; saved Dark mode also checked after restart.
- Both themes captured at approximately 360/393/430 logical widths using densities 480/440/402 with 1080px physical width; original density 420 restored. Automated tests use exact widths.
- Actual Indian search typed on Android. Navigation, menu opening, sheet dismissal and scrolling exercised. No visible overflow or incorrect dish-photo mapping found in reviewed captures. Detailed descriptions remain fully available in item sheets when two-line previews truncate.
- Screenshots in `after/` are actual Android captures; `appearance-preview.jpg` and `viewport-review.jpg` are resized contact sheets of those captures, not generated mockups.

## Outstanding limitations

No known critical regression remains in the tested Phase 1 flows. This is a demo with eight dishes and four fictional kitchens; no ordering, auth, payments or live availability. Existing non-Indian images were preserved rather than re-sourced; some retain smaller source dimensions documented in the earlier validation report. No physical Android handset or performance profiler was used, so sustained frame-rate, memory and device-wide accessibility certification are not claimed. TalkBack was not manually audited. Final branding/release signing remain provisional. The delivered APK is a large universal debug build, not a release/store package.

An automatic approval-review usage-limit failure temporarily interrupted Android capture; after the user requested continuation, execution resumed successfully. All required app assets are present; no unresolved download blocker remains.
