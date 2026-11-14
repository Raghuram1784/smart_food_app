import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/catalog/catalog_repository.dart';
import 'package:smart_food_demo/features/commerce/address_screen.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/location/customer_location_service.dart';
import 'package:smart_food_demo/features/location/delivery_destination.dart';
import 'package:smart_food_demo/features/location/location_picker_screen.dart';
import 'package:smart_food_demo/features/operations/rider_presence_provider.dart';

import 'auth_test.dart' show FakeAuth, session;
import 'commerce_test.dart' show FakeCommerce;

// Synthetic test coordinates only.
const _lat = 17.448123, _lng = 78.391456;

Position _pos({double lat = _lat, double lng = _lng, double acc = 12, DateTime? at}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: at ?? DateTime.now().toUtc(),
      accuracy: acc,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class FakePlatform implements LocationPlatform {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission onRequest = LocationPermission.whileInUse;
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  FutureOr<Position> Function() position = () => _pos();
  int requests = 0, positions = 0, appSettings = 0, locationSettings = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission = onRequest;
  }

  @override
  Future<LocationAccuracyStatus> accuracyStatus() async => accuracy;
  @override
  Future<Position> currentPosition(Duration timeLimit) async {
    positions++;
    return position();
  }

  @override
  Future<bool> openAppSettings() async => (++appSettings) > 0;
  @override
  Future<bool> openLocationSettings() async => (++locationSettings) > 0;
}

class RecordingCommerce extends FakeCommerce {
  final payloads = <String, Json?>{};
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (path.startsWith('addresses') && method != 'GET') {
      payloads['$method $path'] = data;
      calls.add('$method $path');
      return {...?data, 'id': 'saved-1', 'hasConfirmedLocation': data?['latitude'] != null};
    }
    return super.request(method, path, data);
  }
}

Future<LocationFailureKind?> _kind(FakePlatform p) async {
  try {
    await CustomerLocationService(p).currentFix();
    return null;
  } on LocationFailure catch (f) {
    return f.kind;
  }
}

Future<Object?> _openPicker(
  WidgetTester tester,
  FakePlatform platform, {
  Widget Function()? page,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  Object? result = 'not-returned';
  await tester.pumpWidget(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      locationPlatformProvider.overrideWithValue(platform),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<Object?>(
                MaterialPageRoute(builder: (_) => page?.call() ?? const LocationPickerScreen()),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return result;
}

void main() {
  group('CustomerLocationService', () {
    test('success returns a validated real fix; permission is requested only on demand', () async {
      final p = FakePlatform()..permission = LocationPermission.denied;
      final service = CustomerLocationService(p);
      expect(p.requests, 0, reason: 'constructing the service must not prompt');
      final fix = await service.currentFix();
      expect(p.requests, 1);
      expect(fix.latitude, _lat);
      expect(fix.longitude, _lng);
      expect(fix.accuracyMeters, 12);
    });

    test('each failure category is distinguished', () async {
      expect(await _kind(FakePlatform()..serviceEnabled = false), LocationFailureKind.serviceDisabled);
      expect(
        await _kind(FakePlatform()
          ..permission = LocationPermission.denied
          ..onRequest = LocationPermission.denied),
        LocationFailureKind.permissionDenied,
      );
      expect(await _kind(FakePlatform()..permission = LocationPermission.deniedForever),
          LocationFailureKind.permissionDeniedForever);
      expect(await _kind(FakePlatform()..accuracy = LocationAccuracyStatus.reduced),
          LocationFailureKind.approximateOnly);
      expect(await _kind(FakePlatform()..position = () => throw TimeoutException('gps')),
          LocationFailureKind.timeout);
      expect(await _kind(FakePlatform()..position = () => throw const LocationServiceDisabledException()),
          LocationFailureKind.serviceDisabled);
    });

    test('invalid, stale, future and inaccurate fixes are rejected (no fallback location)', () async {
      for (final bad in [_pos(lat: 95), _pos(lng: -181), _pos(lat: 0, lng: 0), _pos(lat: double.nan)]) {
        expect(await _kind(FakePlatform()..position = () => bad), LocationFailureKind.invalidFix);
      }
      expect(
        await _kind(FakePlatform()..position = () => _pos(at: DateTime.now().toUtc().subtract(const Duration(minutes: 5)))),
        LocationFailureKind.staleFix,
      );
      expect(
        await _kind(FakePlatform()..position = () => _pos(at: DateTime.now().toUtc().add(const Duration(minutes: 5)))),
        LocationFailureKind.staleFix,
      );
      expect(await _kind(FakePlatform()..position = () => _pos(acc: 900)), LocationFailureKind.poorAccuracy);
    });
  });

  group('LocationPickerScreen', () {
    testWidgets('no map tiles and no default city until a real fix; failure offers retry, settings and manual entry', (tester) async {
      final completer = Completer<Position>();
      final p = FakePlatform()..position = () => completer.future;
      await _openPicker(tester, p);
      await tester.pump();
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('Getting your current location…'), findsOneWidget);
      completer.completeError(TimeoutException('gps'));
      await tester.pumpAndSettle();
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Enter address manually'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('permission blocked -> App settings action', (tester) async {
      final p = FakePlatform()..permission = LocationPermission.deniedForever;
      await _openPicker(tester, p);
      await tester.pumpAndSettle();
      await tester.tap(find.text('App settings'));
      expect(p.appSettings, 1);
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('GPS disabled -> Location settings, retry then succeeds and shows the map at the fix', (tester) async {
      final p = FakePlatform()..serviceEnabled = false;
      await _openPicker(tester, p);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Location settings'));
      expect(p.locationSettings, 1);
      p.serviceEnabled = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.textContaining('Your GPS: ±12 m'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirming the untouched pin returns DEVICE_GPS with accuracy; cancel returns nothing', (tester) async {
      final p = FakePlatform();
      PickedLocation? picked;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Object? result = 'pending';
      await tester.pumpWidget(ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs), locationPlatformProvider.overrideWithValue(p)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.of(context).push<Object?>(
                MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Recenter and zoom are safe after onMapReady.
      await tester.tap(find.byTooltip('Recenter on my location'));
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();
      picked = result as PickedLocation;
      expect(picked.source, PickedLocationSource.deviceGps);
      expect(picked.latitude, _lat);
      expect(picked.accuracyMeters, 12);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull, reason: 'cancel must not change anything');
      // Picker disposed with its controller: no errors after unmount.
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the map moves the destination pin -> CUSTOMER_MAP_PIN without GPS accuracy', (tester) async {
      final p = FakePlatform();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Object? result;
      await tester.pumpWidget(ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs), locationPlatformProvider.overrideWithValue(p)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.of(context).push<Object?>(
                MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final map = tester.getRect(find.byType(FlutterMap));
      await tester.tapAt(map.center + const Offset(60, 80));
      // flutter_map resolves a single tap after the double-tap timeout.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.textContaining('from you (straight line)'), findsOneWidget);
      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();
      final picked = result as PickedLocation;
      expect(picked.source, PickedLocationSource.customerMapPin);
      expect(picked.accuracyMeters, isNull);
      expect(picked.latitude, isNot(_lat));
    });

    testWidgets('editing a saved pin starts at that pin even when GPS is unavailable', (tester) async {
      final p = FakePlatform()..permission = LocationPermission.deniedForever;
      await _openPicker(tester, p, page: () => const LocationPickerScreen(initialPoint: null, startWithGps: false));
      // initialPoint null and no GPS -> still no default city.
      await tester.pumpAndSettle();
      expect(find.byType(FlutterMap), findsNothing);
    });
  });

  group('AddressEditor', () {
    Future<RecordingCommerce> pumpEditor(WidgetTester tester, Widget editor) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = RecordingCommerce();
      await tester.pumpWidget(const SizedBox()); // fresh navigator for each mount
      await tester.pumpWidget(ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session()),
          commerceRepositoryProvider.overrideWithValue(repo),
          catalogRepositoryProvider.overrideWithValue(OfflineCatalogRepository()),
          locationPlatformProvider.overrideWithValue(FakePlatform()),
        ],
        // Editor sits above a root route, as in the app, so saving can pop it.
        child: MaterialApp(
          initialRoute: '/edit',
          routes: {'/': (_) => const Text('root'), '/edit': (_) => editor},
        ),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    Future<void> fill(WidgetTester tester) async {
      for (final e in {
        'label': 'Family',
        'recipientName': 'Test Person',
        'contactNumber': '9999999999',
        'addressLine1': 'Flat 2, Synthetic Towers',
        'city': 'Hyderabad',
        'postalCode': '500090',
      }.entries) {
        await tester.enterText(find.byKey(ValueKey('address-${e.key}')), e.value);
      }
    }

    testWidgets('saves a confirmed GPS pin with address fields; requires an explicit service-area choice', (tester) async {
      final repo = await pumpEditor(
        tester,
        const AddressEditor(
          location: PickedLocation(latitude: _lat, longitude: _lng, source: PickedLocationSource.deviceGps, accuracyMeters: 12),
        ),
      );
      expect(find.textContaining('device GPS ±12 m'), findsOneWidget);
      await fill(tester);
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();
      expect(repo.payloads, isEmpty, reason: 'no service area chosen yet');
      expect(find.textContaining('Choose a service area'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('address-service-area')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not listed — outside current service areas').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();
      final sent = repo.payloads['POST addresses']!;
      expect(sent['latitude'], _lat);
      expect(sent['longitude'], _lng);
      expect(sent['locationSource'], 'DEVICE_GPS');
      expect(sent['locationAccuracyMeters'], 12);
      expect(sent['localityId'], isNull);
      expect(sent['city'], 'Hyderabad');
      expect(tester.takeException(), isNull);
    });

    testWidgets('editing an existing address keeps its pin, and Remove pin sends no coordinates', (tester) async {
      const existing = {
        'id': 'addr-9',
        'label': 'Home',
        'recipientName': 'Test Person',
        'contactNumber': '9999999999',
        'addressLine1': 'Flat 2, Synthetic Towers',
        'addressLine2': '',
        'landmark': '',
        'city': 'Hyderabad',
        'postalCode': '500090',
        'localityId': 'gachibowli',
        'locality': {'name': 'Gachibowli'},
        'isDefault': true,
        'latitude': 17.45,
        'longitude': 78.38,
        'locationSource': 'CUSTOMER_MAP_PIN',
        'locationAccuracyMeters': null,
      };
      var repo = await pumpEditor(tester, const AddressEditor(address: existing));
      expect(find.textContaining('placed by you'), findsOneWidget);
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();
      var sent = repo.payloads['PATCH addresses/addr-9']!;
      expect(sent['latitude'], 17.45);
      expect(sent['locationSource'], 'CUSTOMER_MAP_PIN');
      expect(sent['localityId'], 'gachibowli');
      expect(find.text('root'), findsOneWidget, reason: 'editor closes after saving');

      repo = await pumpEditor(tester, const AddressEditor(address: existing));
      await tester.tap(find.text('Remove pin'));
      await tester.pumpAndSettle();
      expect(find.text('No map pin'), findsOneWidget);
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();
      sent = repo.payloads['PATCH addresses/addr-9']!;
      expect(sent['latitude'], isNull);
      expect(sent['longitude'], isNull);
      expect(sent['locationSource'], isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('legacy address without coordinates is flagged as unverifiable and stays saveable', (tester) async {
      final repo = await pumpEditor(
        tester,
        const AddressEditor(address: {
          'id': 'legacy-1',
          'label': 'Old',
          'recipientName': 'Test Person',
          'contactNumber': '9999999999',
          'addressLine1': 'Flat 2, Synthetic Towers',
          'addressLine2': '',
          'landmark': '',
          'postalCode': '500090',
          'localityId': 'madhapur',
          'isDefault': false,
        }),
      );
      expect(find.text('No map pin'), findsOneWidget);
      expect(find.textContaining('delivery distance can\'t be verified'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('address-city')), 'Hyderabad');
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();
      final sent = repo.payloads['PATCH addresses/legacy-1']!;
      expect(sent['latitude'], isNull);
      expect(sent['locationSource'], isNull);
    });
  });

  test('serviceability parsing never claims a distance without the server providing one', () {
    final unverified = RestaurantServiceability.fromJson({
      'restaurantId': 'r1', 'eligible': true, 'status': 'SERVICEABLE_UNVERIFIED_DISTANCE', 'basis': 'SERVICE_AREA',
      'straightLineMeters': null, 'reason': 'x',
    });
    expect(unverified.shortLabel, 'Delivers to this area · distance not verified');
    final verified = RestaurantServiceability.fromJson({
      'restaurantId': 'r1', 'eligible': true, 'status': 'SERVICEABLE', 'basis': 'VERIFIED_DISTANCE',
      'straightLineMeters': 1200, 'reason': 'x',
    });
    expect(verified.shortLabel, contains('1.2 km straight line'));
    final no = RestaurantServiceability.fromJson({'restaurantId': 'r1', 'eligible': false, 'status': 'NOT_SERVICEABLE'});
    expect(no.eligible, isFalse);
  });

  test('customer and rider location state are isolated', () {
    final c = ProviderContainer(overrides: [locationPlatformProvider.overrideWithValue(FakePlatform())]);
    addTearDown(c.dispose);
    // Rider presence remains its own provider; the customer service never touches it.
    expect(c.read(customerLocationServiceProvider), isA<CustomerLocationService>());
    expect(identical(customerLocationServiceProvider, riderPresenceProvider), isFalse);
  });
}
