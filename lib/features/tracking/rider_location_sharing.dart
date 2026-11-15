import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_provider.dart';
import 'tracking_api.dart';

/// Rider live location sharing for ONE accepted, active delivery.
///
/// Design rules (F4, learned from the old mandatory-GPS presence):
/// - Go Online and invitations never depend on GPS; this only starts after acceptance.
/// - Uses real hardware fixes only; nothing is simulated or interpolated here.
/// - Android runs a foreground location service with a visible notification so sharing
///   continues with the screen off; it stops on delivery, cancellation or sign-out.
/// - Every failure is caught and shown as a state; it never crashes the rider screen or
///   blocks pickup/delivery actions.
enum SharingStatus { idle, starting, sharing, permissionDenied, permissionDeniedForever, serviceDisabled, error, ended }

@immutable
class SharingState {
  final SharingStatus status;
  final String? orderId;
  final DateTime? lastSentAt;
  final double? lastAccuracy;
  final String? message;
  const SharingState(this.status, {this.orderId, this.lastSentAt, this.lastAccuracy, this.message});
  bool get active => status == SharingStatus.sharing || status == SharingStatus.starting;
  SharingState copy({SharingStatus? status, DateTime? lastSentAt, double? lastAccuracy, String? message, bool clearMessage = false}) =>
      SharingState(status ?? this.status, orderId: orderId, lastSentAt: lastSentAt ?? this.lastSentAt, lastAccuracy: lastAccuracy ?? this.lastAccuracy, message: clearMessage ? null : message ?? this.message);
}

/// Device seam so permission and stream behaviour can be tested without hardware.
abstract class RiderLocationSource {
  Future<bool> serviceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Stream<Position> positions();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

class GeolocatorRiderSource implements RiderLocationSource {
  const GeolocatorRiderSource();
  @override
  Future<bool> serviceEnabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() => Geolocator.requestPermission();
  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
  @override
  Stream<Position> positions() {
    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            // Time-based sampling (no distance filter) so a rider waiting at a signal still sends the
            // heartbeat that keeps the customer's view live; uploads are throttled separately.
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 5),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Sharing live location',
              notificationText: 'Your customer can see you for this delivery. Stops automatically when it is delivered.',
              notificationChannelName: 'Live delivery tracking',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}

/// Throttle: at most one upload per [minInterval]; send when moved [minMoveMeters] or every [heartbeat]
/// (keeps the customer's view LIVE while waiting at a light without spamming the server).
class SendThrottle {
  final Duration minInterval, heartbeat;
  final double minMoveMeters;
  const SendThrottle({this.minInterval = const Duration(seconds: 5), this.heartbeat = const Duration(seconds: 15), this.minMoveMeters = 10});
  bool shouldSend({required DateTime now, DateTime? lastSentAt, double? movedMeters}) {
    if (lastSentAt == null) return true;
    final elapsed = now.difference(lastSentAt);
    if (elapsed < minInterval) return false;
    return (movedMeters ?? double.infinity) >= minMoveMeters || elapsed >= heartbeat;
  }
}

final riderLocationSourceProvider = Provider<RiderLocationSource>((ref) => const GeolocatorRiderSource());

class RiderLocationSharing extends Notifier<SharingState> {
  StreamSubscription<Position>? _sub;
  Position? _lastSent;
  bool _uploading = false;
  final throttle = const SendThrottle();

  @override
  SharingState build() {
    // Sign-out (or account switch) always stops sharing.
    ref.listen(authProvider, (prev, next) {
      if (next.asData?.value == null) stop(ended: true);
    });
    ref.onDispose(() => _sub?.cancel());
    return const SharingState(SharingStatus.idle);
  }

  RiderLocationSource get _source => ref.read(riderLocationSourceProvider);

  /// Starts sharing for [orderId]. Requests permission only when [ask] (rider tapped the button).
  Future<void> start(String orderId, {bool ask = true}) async {
    if (state.active && state.orderId == orderId) return;
    await _cancel();
    state = SharingState(SharingStatus.starting, orderId: orderId);
    try {
      if (!await _source.serviceEnabled()) {
        state = SharingState(SharingStatus.serviceDisabled, orderId: orderId, message: 'Turn on Location (GPS) to share your live position.');
        return;
      }
      var permission = await _source.checkPermission();
      if (permission == LocationPermission.denied && ask) permission = await _source.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        state = SharingState(SharingStatus.permissionDeniedForever, orderId: orderId, message: 'Location permission is blocked. Allow it in Settings to share live location.');
        return;
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
        state = SharingState(SharingStatus.permissionDenied, orderId: orderId, message: 'Allow location to let your customer follow this delivery. Deliveries still work without it.');
        return;
      }
      _sub = _source.positions().listen(_onFix, onError: (Object e) {
        final disabled = e is LocationServiceDisabledException;
        state = state.copy(status: disabled ? SharingStatus.serviceDisabled : SharingStatus.error,
            message: disabled ? 'Location was turned off. Turn it on to resume sharing.' : 'Location temporarily unavailable. Retrying…');
      }, cancelOnError: false);
      state = state.copy(status: SharingStatus.sharing, message: 'Waiting for the first GPS fix…');
    } catch (_) {
      state = SharingState(SharingStatus.error, orderId: orderId, message: 'Could not start location sharing. Deliveries still work.');
    }
  }

  Future<void> _onFix(Position p) async {
    final id = state.orderId;
    if (id == null || _uploading) return;
    final now = DateTime.now();
    final moved = _lastSent == null ? null : Geolocator.distanceBetween(_lastSent!.latitude, _lastSent!.longitude, p.latitude, p.longitude);
    if (!throttle.shouldSend(now: now, lastSentAt: state.lastSentAt, movedMeters: moved)) return;
    _uploading = true;
    try {
      await ref.read(trackingApiProvider).publish(id,
          latitude: p.latitude, longitude: p.longitude, accuracyMeters: p.accuracy,
          headingDegrees: p.heading >= 0 && p.heading <= 360 && p.speed > 0.5 ? p.heading : null,
          speedMps: p.speed >= 0 ? p.speed : null, recordedAt: p.timestamp);
      _lastSent = p;
      state = state.copy(status: SharingStatus.sharing, lastSentAt: now, lastAccuracy: p.accuracy, clearMessage: true);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 410 || code == 403) {
        await stop(ended: true); // delivered, canceled or reassigned: tracking ends on the server
      } else if (code == 422) {
        state = state.copy(message: 'GPS signal is weak. Waiting for a better fix…');
      } else if (code == 409 || code == 429) {
        // Out-of-order or throttled: harmless, next fix will be sent.
      } else {
        state = state.copy(message: 'Network issue. Your location will resume automatically.');
      }
    } catch (_) {
      state = state.copy(message: 'Location temporarily unavailable. Retrying…');
    } finally {
      _uploading = false;
    }
  }

  Future<void> _cancel() async {
    final s = _sub;
    _sub = null;
    _lastSent = null;
    try {
      await s?.cancel(); // also stops the Android foreground service and its notification
    } catch (_) {}
  }

  Future<void> stop({bool ended = false}) async {
    await _cancel();
    state = SharingState(ended ? SharingStatus.ended : SharingStatus.idle);
  }

  Future<void> openSettings() async {
    try {
      if (state.status == SharingStatus.serviceDisabled) {
        await _source.openLocationSettings();
      } else {
        await _source.openAppSettings();
      }
    } catch (_) {}
  }
}

final riderLocationSharingProvider = NotifierProvider<RiderLocationSharing, SharingState>(RiderLocationSharing.new);
