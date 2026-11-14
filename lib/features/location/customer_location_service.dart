import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// A real device GPS fix, validated for range, freshness and accuracy.
class DeviceFix {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
  const DeviceFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });
}

enum LocationFailureKind {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  approximateOnly,
  timeout,
  invalidFix,
  staleFix,
  poorAccuracy,
}

class LocationFailure implements Exception {
  final LocationFailureKind kind;
  final String message;
  const LocationFailure(this.kind, this.message);

  /// Whether the fix is in Android settings rather than retrying.
  bool get needsAppSettings =>
      kind == LocationFailureKind.permissionDeniedForever ||
      kind == LocationFailureKind.approximateOnly;
  bool get needsLocationSettings => kind == LocationFailureKind.serviceDisabled;

  @override
  String toString() => message;
}

/// Thin seam over geolocator so permission/GPS states can be tested without a device.
abstract class LocationPlatform {
  Future<bool> isServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<LocationAccuracyStatus> accuracyStatus();
  Future<Position> currentPosition(Duration timeLimit);
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

class GeolocatorLocationPlatform implements LocationPlatform {
  const GeolocatorLocationPlatform();
  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() => Geolocator.requestPermission();
  @override
  Future<LocationAccuracyStatus> accuracyStatus() => Geolocator.getLocationAccuracy();
  @override
  Future<Position> currentPosition(Duration timeLimit) => Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeLimit),
      );
  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

/// Customer-side location lookup. Independent of rider presence: it never
/// streams, never reports to the server, and only runs when the customer asks.
class CustomerLocationService {
  final LocationPlatform platform;
  final DateTime Function() clock;
  CustomerLocationService(this.platform, {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  static const timeLimit = Duration(seconds: 25);
  static const maxFixAge = Duration(minutes: 2);
  static const maxFutureSkew = Duration(minutes: 1);
  static const maxAccuracyMeters = 500.0;

  /// Requests permission only now (when the customer chose "Use current location").
  Future<DeviceFix> currentFix() async {
    if (!await platform.isServiceEnabled()) {
      throw const LocationFailure(
        LocationFailureKind.serviceDisabled,
        'Location is turned off on this device. Turn it on to use your current location.',
      );
    }
    var permission = await platform.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await platform.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        LocationFailureKind.permissionDeniedForever,
        'Location permission is blocked. Allow it in App Settings → Permissions → Location, or choose your address manually.',
      );
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationFailure(
        LocationFailureKind.permissionDenied,
        'Location permission was not granted. You can retry or choose your address manually.',
      );
    }
    try {
      if (await platform.accuracyStatus() == LocationAccuracyStatus.reduced) {
        throw const LocationFailure(
          LocationFailureKind.approximateOnly,
          'Only approximate location is allowed. Turn on "Use precise location" in App Settings, or place the pin on the map yourself.',
        );
      }
    } on LocationFailure {
      rethrow;
    } catch (_) {
      // Precision status unsupported on this platform.
    }

    final Position position;
    try {
      position = await platform.currentPosition(timeLimit);
    } on LocationServiceDisabledException {
      throw const LocationFailure(
        LocationFailureKind.serviceDisabled,
        'Location was turned off. Turn it on and retry.',
      );
    } on PermissionDeniedException {
      throw const LocationFailure(
        LocationFailureKind.permissionDenied,
        'Location permission was revoked.',
      );
    } catch (_) {
      throw const LocationFailure(
        LocationFailureKind.timeout,
        'Could not get a GPS fix in time. Move near a window or outdoors and retry, or place the pin on the map.',
      );
    }
    return validate(position);
  }

  DeviceFix validate(Position p) {
    final lat = p.latitude, lng = p.longitude, acc = p.accuracy;
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180 ||
        (lat == 0 && lng == 0)) {
      throw const LocationFailure(
        LocationFailureKind.invalidFix,
        'The device returned an invalid location. Retry, or place the pin on the map.',
      );
    }
    final now = clock().toUtc();
    final ts = p.timestamp.toUtc();
    if (now.difference(ts) > maxFixAge || ts.difference(now) > maxFutureSkew) {
      throw const LocationFailure(
        LocationFailureKind.staleFix,
        'The device location is out of date. Retry to get a fresh GPS fix.',
      );
    }
    if (!acc.isFinite || acc < 0 || acc > maxAccuracyMeters) {
      throw LocationFailure(
        LocationFailureKind.poorAccuracy,
        'GPS accuracy is too low (±${acc.isFinite ? acc.round() : '?'} m). Retry outdoors, or place the pin on the map.',
      );
    }
    return DeviceFix(latitude: lat, longitude: lng, accuracyMeters: acc, timestamp: ts);
  }
}

final locationPlatformProvider = Provider<LocationPlatform>(
  (ref) => const GeolocatorLocationPlatform(),
);
final customerLocationServiceProvider = Provider<CustomerLocationService>(
  (ref) => CustomerLocationService(ref.watch(locationPlatformProvider)),
);
