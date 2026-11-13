# Food Delivery Demo — Phase 1

An offline-first Android Flutter foundation with editorial light and culinary noir appearances. Branding lives in `lib/core/design.dart` (Android display name: AndroidManifest.xml). No backend, ordering, authentication or payment flow is implemented.

## Run

```powershell
flutter pub get
flutter run -d emulator-5554
```

Requires Flutter 3.47.5 / Dart 3.13.4 or a compatible newer SDK and an Android SDK. The lockfile records resolved versions. To build the installable debug demo: `flutter build apk --debug`.

## Implemented

- Discover: demo neighbourhood selector, greeting, search entry, photographic categories, featured meal, under-₹250 collection, restaurant recommendations.
- Explore: case-insensitive multiword dish, restaurant and cuisine search; category and price filters; clear/reset controls and empty state.
- Restaurant: photographic hero, cuisine, description, illustrative rating/time, sectioned local menu and scrollable dish details.
- You: explicit demo profile and persisted Light, Dark and System default choices. Save failures produce a retry message.
- Shared bottom navigation and go_router detail routes, invalid-route recovery, back navigation, Material feedback and modal sheets.
- Bundled Bricolage Grotesque, Sora and optimized photographs; image placeholders and failure states. No runtime asset requests.

## Structure / authored files

```text
lib/
  main.dart                         # async preferences bootstrap
  app.dart                          # router, shell, shared theme selection
  core/
    design.dart                     # brand, spacing, ThemeData/ColorScheme
    providers.dart                  # Riverpod preferences/location, future Dio client
  features/
    catalog/catalog.dart            # typed fictional catalog and pure search
    discovery/home_screen.dart
    discovery/search_screen.dart
    restaurant/restaurant_screen.dart
    profile/profile_screen.dart
  shared/components.dart            # photos, cards, dish tiles and details sheet
assets/
  fonts/                            # local fonts and OFL licences
  images/{food,restaurants,categories,hero}/
android/                            # Flutter-generated native Android foundation
 test/widget_test.dart              # catalog, persistence, responsive interaction tests
 tool/                              # repeatable asset download/optimization scripts
 docs/                              # credits, validation and screenshots
```

Created from an empty workspace using Flutter tooling. Generated Android files are preserved except the human-readable application label. `pubspec.yaml` registers dependencies, fonts and image directories. No supplied scaffold existed.

## Dependencies

Flutter SDK, flutter_riverpod 3.5.0, go_router 18.1.4, dio 5.11.1, shared_preferences 2.5.6. Dio is provided for future integration and makes no requests. Flutter test and flutter_lints support validation. No code generation required.

## Data and phase boundaries

Four fictional kitchens and eight distinct dishes. Original dish IDs and prices are retained. Prices are sample INR item prices; filters do not calculate total delivered cost. Location is an in-session demo selection and does not change availability. Appearance is persisted locally. System mode follows the OS. Both appearances use the same screens, catalog and photos. No live service claims, AI rankings, cart, checkout, payments, tracking or authentication.

Photo attribution and licensing: [docs/ASSET_CREDITS.md](docs/ASSET_CREDITS.md). Font licence files ship in the repository. The original photographs are stock food illustrations, not photographs of the fictional kitchens. Release signing and final brand identity remain future configuration work.

Validation results and limitations: [docs/VALIDATION.md](docs/VALIDATION.md).
Actual Android screenshots: [appearance preview](docs/screenshots/appearance-preview.jpg) and [viewport review](docs/screenshots/viewport-review.jpg).

## Current visual refinement

See [before/after audit and validation](docs/refinement/REPORT.md), [new photo/font manifest](docs/refinement/ASSETS.md), and [actual Android captures](docs/refinement/after/). Default typography: Bricolage Grotesque + Sora. For the archived font comparison build only: `flutter build apk --debug --dart-define=EDITORIAL_FONT=Fraunces`.
