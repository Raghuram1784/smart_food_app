import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../commerce/commerce_repository.dart';

/// GPS-free rider availability. Online = willing to receive delivery invitations.
/// No location permission is requested and no coordinates are sent.
class RiderPresenceState {
  final bool isOnline;
  final bool isAvailable;
  final bool busy; // a toggle request is in flight
  final bool loaded;
  final Json? activeAssignment;
  final String? error;
  const RiderPresenceState({
    this.isOnline = false,
    this.isAvailable = false,
    this.busy = false,
    this.loaded = false,
    this.activeAssignment,
    this.error,
  });

  bool get onDelivery => activeAssignment != null;

  RiderPresenceState copyWith({
    bool? isOnline,
    bool? isAvailable,
    bool? busy,
    bool? loaded,
    Json? activeAssignment,
    bool clearAssignment = false,
    String? error,
  }) => RiderPresenceState(
    isOnline: isOnline ?? this.isOnline,
    isAvailable: isAvailable ?? this.isAvailable,
    busy: busy ?? this.busy,
    loaded: loaded ?? this.loaded,
    activeAssignment: clearAssignment ? null : (activeAssignment ?? this.activeAssignment),
    error: error,
  );
}

/// Human-readable, category-specific message (never a generic "connection lost").
String presenceError(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    if (e.response == null) {
      return 'Cannot reach the server. Check that the backend is running (and adb reverse for USB).';
    }
    if (status == 401) return 'Your session ended. Please sign in again.';
    if (status == 403) return 'This account is not a delivery partner.';
    if (status == 404) return 'Server is out of date (HTTP 404). Restart the backend.';
    return commerceError(e);
  }
  return 'Unexpected error. Please retry.';
}

class RiderPresenceNotifier extends Notifier<RiderPresenceState> {
  bool _disposed = false;

  @override
  RiderPresenceState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.listen(authProvider, (_, next) {
      final s = next.asData?.value;
      if (s == null || !s.user.roles.contains('DELIVERY_PARTNER')) {
        state = const RiderPresenceState();
      }
    });
    Future.microtask(refresh);
    return const RiderPresenceState();
  }

  void _apply(dynamic raw) {
    if (_disposed || raw is! Map) return;
    final a = raw['activeAssignment'];
    state = state.copyWith(
      isOnline: raw['isOnline'] == true,
      isAvailable: raw['isAvailable'] == true,
      activeAssignment: a is Map ? Json.from(a) : null,
      clearAssignment: a is! Map,
      loaded: true,
      busy: false,
    );
  }

  Future<void> refresh() async {
    try {
      _apply(await ref.read(commerceRepositoryProvider).request('GET', 'rider/presence/me'));
    } catch (e) {
      if (!_disposed) state = state.copyWith(loaded: true, error: presenceError(e));
    }
  }

  Future<void> setOnline(bool online) async {
    if (state.busy) return; // de-duplicate rapid taps
    state = state.copyWith(busy: true);
    try {
      _apply(
        await ref.read(commerceRepositoryProvider).request(
          'POST',
          online ? 'rider/presence/online' : 'rider/presence/offline',
        ),
      );
    } catch (e) {
      if (!_disposed) state = state.copyWith(busy: false, error: presenceError(e));
    }
  }
}

final riderPresenceProvider = NotifierProvider<RiderPresenceNotifier, RiderPresenceState>(
  RiderPresenceNotifier.new,
);

/// Pending delivery invitations, always read from the backend (PostgreSQL).
final riderOffersProvider = FutureProvider.autoDispose<List<Json>>((ref) async {
  final presence = ref.watch(riderPresenceProvider.select((p) => (p.isOnline, p.onDelivery)));
  if (!presence.$1 || presence.$2) return const [];
  final raw = await ref.watch(commerceRepositoryProvider).request('GET', 'operations/delivery/offers');
  final list = (raw is Map ? raw['offers'] : null) as List? ?? const [];
  return [for (final o in list) Json.from(o as Map)];
});
