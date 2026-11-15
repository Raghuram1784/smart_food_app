import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/commerce/live_orders.dart';
import 'package:smart_food_demo/features/tracking/rider_location_sharing.dart';
import 'package:smart_food_demo/features/tracking/track_order_screen.dart';

import 'auth_test.dart' show FakeAuth, session;
import 'commerce_test.dart' show FakeCommerce;

const oid = '33333333-3333-4333-8333-333333333333';

Json trackFixture({String status = 'OUT_FOR_DELIVERY', Json? riderLocation, String freshness = 'LIVE', bool withDestination = true, bool terminal = false}) => {
      'orderId': oid, 'orderNumber': 'FD-TRACK-1', 'status': status, 'terminal': terminal, 'version': 9, 'trackingActive': !terminal,
      'restaurant': {'name': 'Deccan Handi & Dum', 'location': null, 'locationNote': 'Restaurant pickup point not configured yet'},
      'destination': withDestination ? {'latitude': 17.4401, 'longitude': 78.3489, 'source': 'SAVED_ADDRESS'} : null,
      'destinationNote': withDestination ? null : 'Confirm your delivery pin to see distance and arrival time',
      'rider': {'name': 'Ravi', 'location': riderLocation, 'freshness': freshness, 'ageSeconds': riderLocation == null ? null : 3},
      'eta': terminal
          ? {'phase': 'DELIVERED', 'seconds': null, 'arrivalAt': null, 'distanceMeters': null, 'straightLineMeters': null, 'source': null, 'basis': 'Delivered', 'scheduleStatus': null}
          : {'phase': 'TO_CUSTOMER', 'seconds': 600, 'arrivalAt': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(), 'distanceMeters': null, 'straightLineMeters': 4600, 'source': 'ESTIMATE', 'basis': 'estimated travel to you (no road route available)', 'scheduleStatus': 'ON_TRACK'},
      'route': null, 'routing': {'provider': 'none', 'configured': false},
      'schedule': {'scheduledDeliveryAt': DateTime.now().add(const Duration(minutes: 20)).toUtc().toIso8601String(), 'windowStart': DateTime.now().add(const Duration(minutes: 15)).toUtc().toIso8601String(), 'windowEnd': DateTime.now().add(const Duration(minutes: 25)).toUtc().toIso8601String()},
      'serverTime': DateTime.now().toUtc().toIso8601String(), 'rules': {'liveSeconds': 30, 'unavailableSeconds': 120},
    };

Json fix(double lat, double lng, {int ageSeconds = 2}) => {'latitude': lat, 'longitude': lng, 'accuracyMeters': 8, 'headingDegrees': 90, 'speedMps': 6, 'recordedAt': DateTime.now().subtract(Duration(seconds: ageSeconds)).toUtc().toIso8601String()};

class TrackFake extends FakeCommerce {
  Json view;
  int views = 0;
  final published = <Json>[];
  Object? publishFailure;
  TrackFake(this.view);
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (path.startsWith('tracking/')) {
      if (method == 'GET') {
        views++;
        return view;
      }
      if (path.endsWith('/location')) {
        if (publishFailure != null) throw publishFailure!;
        published.add(data!);
        return {'accepted': true};
      }
      return view;
    }
    return super.request(method, path, data);
  }
}

class FakeSource implements RiderLocationSource {
  bool enabled = true;
  LocationPermission permission;
  LocationPermission afterRequest;
  int requests = 0, listens = 0;
  final controller = StreamController<Position>.broadcast();
  bool cancelled = false;
  FakeSource({this.permission = LocationPermission.whileInUse, LocationPermission? afterRequest}) : afterRequest = afterRequest ?? permission;
  @override
  Future<bool> serviceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission = afterRequest;
  }
  @override
  Stream<Position> positions() {
    listens++;
    controller.onCancel = () => cancelled = true;
    return controller.stream;
  }
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
}

Position pos(double lat, double lng, {DateTime? at}) => Position(latitude: lat, longitude: lng, timestamp: at ?? DateTime.now(), accuracy: 6, altitude: 0, altitudeAccuracy: 0, heading: 45, headingAccuracy: 5, speed: 7, speedAccuracy: 1);

Future<ProviderContainer> riderContainer(TrackFake repo, FakeSource source) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    preferencesProvider.overrideWithValue(prefs),
    authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session('DELIVERY_PARTNER')),
    commerceRepositoryProvider.overrideWithValue(repo),
    riderLocationSourceProvider.overrideWithValue(source),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<StreamController<LiveOrderUpdate>> mountTrack(WidgetTester tester, TrackFake repo, {Size size = const Size(390, 860), double text = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final live = StreamController<LiveOrderUpdate>.broadcast();
  addTearDown(live.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session()),
      commerceRepositoryProvider.overrideWithValue(repo),
      liveOrdersProvider.overrideWith((ref) => live.stream),
    ],
    child: MediaQuery(data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)), child: MaterialApp(theme: appTheme(Brightness.light), home: const TrackOrderScreen(orderId: oid))),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return live;
}

Future<void> settle(WidgetTester tester, [int frames = 15]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('rules', () {
    test('freshness: waiting, live, stale, unavailable', () {
      final now = DateTime.utc(2026, 11, 15, 10);
      expect(fixFreshness(null, now), 'WAITING');
      expect(fixFreshness(now.subtract(const Duration(seconds: 10)), now), 'LIVE');
      expect(fixFreshness(now.subtract(const Duration(seconds: 45)), now), 'STALE');
      expect(fixFreshness(now.subtract(const Duration(minutes: 5)), now), 'UNAVAILABLE');
      expect(agoText(30), '30 seconds ago');
      expect(agoText(125), '2 min ago');
    });
    test('send throttle: 5 s minimum, move 10 m or 15 s heartbeat', () {
      const t = SendThrottle();
      final t0 = DateTime(2026, 11, 15, 10);
      expect(t.shouldSend(now: t0), isTrue);
      expect(t.shouldSend(now: t0.add(const Duration(seconds: 3)), lastSentAt: t0, movedMeters: 200), isFalse);
      expect(t.shouldSend(now: t0.add(const Duration(seconds: 6)), lastSentAt: t0, movedMeters: 25), isTrue);
      expect(t.shouldSend(now: t0.add(const Duration(seconds: 6)), lastSentAt: t0, movedMeters: 2), isFalse);
      expect(t.shouldSend(now: t0.add(const Duration(seconds: 16)), lastSentAt: t0, movedMeters: 0), isTrue);
    });
  });

  group('rider sharing', () {
    test('permission denied: no stream, clear message, deliveries unaffected', () async {
      final source = FakeSource(permission: LocationPermission.denied);
      final c = await riderContainer(TrackFake(trackFixture()), source);
      await c.read(riderLocationSharingProvider.notifier).start(oid);
      expect(source.requests, 1);
      expect(c.read(riderLocationSharingProvider).status, SharingStatus.permissionDenied);
      expect(source.listens, 0);
    });
    test('auto-start never prompts; blocked permission and GPS off are recoverable states', () async {
      final source = FakeSource(permission: LocationPermission.denied);
      final c = await riderContainer(TrackFake(trackFixture()), source);
      await c.read(riderLocationSharingProvider.notifier).start(oid, ask: false);
      expect(source.requests, 0, reason: 'no permission prompt without a rider tap');
      source.permission = LocationPermission.deniedForever;
      await c.read(riderLocationSharingProvider.notifier).start(oid);
      expect(c.read(riderLocationSharingProvider).status, SharingStatus.permissionDeniedForever);
      source
        ..permission = LocationPermission.whileInUse
        ..enabled = false;
      await c.read(riderLocationSharingProvider.notifier).start(oid);
      expect(c.read(riderLocationSharingProvider).status, SharingStatus.serviceDisabled);
    });
    test('real fixes are uploaded with throttling; delivery completion (410) stops the stream', () async {
      final source = FakeSource();
      final repo = TrackFake(trackFixture());
      final c = await riderContainer(repo, source);
      await c.read(riderLocationSharingProvider.notifier).start(oid);
      expect(c.read(riderLocationSharingProvider).status, SharingStatus.sharing);
      source.controller.add(pos(17.4483, 78.3915));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      source.controller.add(pos(17.4490, 78.3920)); // within 5 s: throttled
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.published.length, 1);
      expect(repo.published.single['latitude'], 17.4483);
      expect(repo.published.single['accuracyMeters'], 6);
      expect(c.read(riderLocationSharingProvider).lastSentAt, isNotNull);
      repo.publishFailure = DioException(requestOptions: RequestOptions(), response: Response(requestOptions: RequestOptions(), statusCode: 410));
      // Simulate the next eligible fix after the throttle window.
      final n = c.read(riderLocationSharingProvider.notifier);
      n.state = n.state.copy(lastSentAt: DateTime.now().subtract(const Duration(seconds: 30)));
      source.controller.add(pos(17.4500, 78.3930));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(riderLocationSharingProvider).status, SharingStatus.ended);
      expect(source.cancelled, isTrue, reason: 'foreground location stream released after OTP delivery');
    });
    test('network and stream errors never throw; sharing keeps running', () async {
      final source = FakeSource();
      final repo = TrackFake(trackFixture())..publishFailure = DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError);
      final c = await riderContainer(repo, source);
      await c.read(riderLocationSharingProvider.notifier).start(oid);
      source.controller.add(pos(17.4483, 78.3915));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(riderLocationSharingProvider).status, SharingStatus.sharing);
      expect(c.read(riderLocationSharingProvider).message, contains('Network issue'));
      source.controller.addError(const LocationServiceDisabledException());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(riderLocationSharingProvider).status, SharingStatus.serviceDisabled);
    });
  });

  group('customer tracking screen', () {
    testWidgets('no coordinates yet: waiting message, no map, no LIVE badge; pin can be confirmed', (tester) async {
      await mountTrack(tester, TrackFake(trackFixture(status: 'PREPARING', freshness: 'WAITING', withDestination: false)));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('track-no-map')), findsOneWidget);
      expect(find.text('Waiting for rider location'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-badge')), findsNothing);
      expect(find.byKey(const ValueKey('confirm-pin')), findsWidgets);
    });

    testWidgets('first GPS fix initializes the map with rider and home markers, LIVE badge and labeled estimate', (tester) async {
      final repo = TrackFake(trackFixture(riderLocation: fix(17.4483, 78.3915)));
      await mountTrack(tester, repo, size: const Size(360, 780), text: 1.3);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('track-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('rider-marker')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('eta-source')), findsOneWidget);
      expect(find.text('Estimate'), findsOneWidget);
      expect(find.textContaining('straight line'), findsOneWidget, reason: 'never presented as road distance');
      expect(find.byKey(const ValueKey('schedule-status')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('track-recenter')));
      await settle(tester, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('live socket fix moves the marker smoothly; stale data drops the LIVE badge', (tester) async {
      final repo = TrackFake(trackFixture(riderLocation: fix(17.4483, 78.3915)));
      final live = await mountTrack(tester, repo);
      await settle(tester);
      // The camera follows the rider, so compare the marker's map coordinate, not its screen offset.
      LatLng riderAt() => tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.last.point;
      final before = riderAt();
      live.add(LiveOrderUpdate('Live updates connected', orderId: oid, location: fix(17.4440, 78.3700, ageSeconds: 0)));
      await tester.pump(); // event delivered
      await tester.pump(const Duration(milliseconds: 16)); // first animation tick
      await tester.pump(const Duration(milliseconds: 450));
      final mid = riderAt();
      await settle(tester, 15);
      final after = riderAt();
      expect(after.latitude, closeTo(17.4440, 1e-9), reason: 'ends exactly on the received fix');
      expect(mid.latitude, lessThan(before.latitude), reason: 'marker animates toward the new fix');
      expect(mid.latitude, greaterThan(after.latitude), reason: 'intermediate frame, not a jump');
      // Another order's fix is ignored.
      live.add(LiveOrderUpdate('Live updates connected', orderId: 'other', location: fix(17.0, 78.0, ageSeconds: 0)));
      await settle(tester, 3);
      expect(riderAt(), after);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stale fix: last-updated text, no LIVE badge', (tester) async {
      await mountTrack(tester, TrackFake(trackFixture(riderLocation: fix(17.4483, 78.3915, ageSeconds: 50), freshness: 'STALE')));
      await settle(tester);
      expect(find.byKey(const ValueKey('live-badge')), findsNothing);
      expect(find.textContaining('Last updated'), findsWidgets);
    });

    testWidgets('unavailable fix: temporarily unavailable message, no LIVE badge', (tester) async {
      await mountTrack(tester, TrackFake(trackFixture(riderLocation: fix(17.4483, 78.3915, ageSeconds: 400), freshness: 'UNAVAILABLE')));
      await settle(tester);
      expect(find.byKey(const ValueKey('live-badge')), findsNothing);
      expect(find.textContaining('temporarily unavailable'), findsWidgets);
    });

    testWidgets('socket reconnect re-reads the authoritative view; delivery ends tracking', (tester) async {
      final repo = TrackFake(trackFixture(riderLocation: fix(17.4483, 78.3915)));
      final live = await mountTrack(tester, repo);
      await settle(tester);
      final views = repo.views;
      live.add(const LiveOrderUpdate('Live updates connected', reconcile: true));
      await settle(tester, 3);
      expect(repo.views, views + 1, reason: 'recovery after reconnect');
      repo.view = trackFixture(status: 'DELIVERED', terminal: true, freshness: 'ENDED');
      live.add(const LiveOrderUpdate('Live updates connected', orderId: oid, eventType: 'ORDER_DELIVERED'));
      await settle(tester);
      expect(find.byKey(const ValueKey('rider-marker')), findsNothing);
      expect(find.byKey(const ValueKey('live-badge')), findsNothing);
      expect(find.text('Delivered'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
