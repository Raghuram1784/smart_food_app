import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../commerce/commerce_repository.dart';

/// F4 live tracking API. The server is authoritative for authorization, freshness and ETA.
class TrackingApi {
  final CommerceRepository repo;
  TrackingApi(this.repo);

  Future<Json> view(String orderId) async => Json.from(await repo.request('GET', 'tracking/orders/$orderId'));

  /// Rider only: one real device fix for an active delivery.
  Future<void> publish(String orderId, {required double latitude, required double longitude, required double accuracyMeters, double? headingDegrees, double? speedMps, required DateTime recordedAt}) =>
      repo.request('POST', 'tracking/orders/$orderId/location', {
        'latitude': latitude, 'longitude': longitude, 'accuracyMeters': accuracyMeters,
        'headingDegrees': ?headingDegrees, 'speedMps': ?speedMps, 'recordedAt': recordedAt.toUtc().toIso8601String(),
      });

  Future<Json> setDestination(String orderId, double latitude, double longitude) async =>
      Json.from(await repo.request('PUT', 'tracking/orders/$orderId/destination', {'latitude': latitude, 'longitude': longitude}));

  Future<Json> setPickupLocation(String restaurantId, double latitude, double longitude, {double? accuracyMeters}) async =>
      Json.from(await repo.request('PUT', 'tracking/restaurants/$restaurantId/pickup-location', {'latitude': latitude, 'longitude': longitude, 'accuracyMeters': ?accuracyMeters}));
}

final trackingApiProvider = Provider<TrackingApi>((ref) => TrackingApi(ref.watch(commerceRepositoryProvider)));
final trackingProvider = FutureProvider.autoDispose.family<Json, String>((ref, orderId) => ref.watch(trackingApiProvider).view(orderId));

/// Orders a customer can follow on the map: accepted and not finished.
bool isTrackable(Json order) => ['ACCEPTED', 'PREPARING', 'READY_FOR_PICKUP', 'PICKED_UP', 'OUT_FOR_DELIVERY'].contains(order['status']);

/// Prominent entry to live tracking (My Orders and order details).
class TrackOrderButton extends StatelessWidget {
  final String orderId;
  final bool compact;
  const TrackOrderButton({super.key, required this.orderId, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      visualDensity: compact ? VisualDensity.compact : null,
      minimumSize: compact ? const Size(40, 36) : const Size.fromHeight(48),
    );
    return FilledButton.icon(
      key: ValueKey('track-$orderId'),
      style: style,
      onPressed: () => context.push('/orders/$orderId/track'),
      icon: Icon(Icons.two_wheeler, size: compact ? 18 : 22),
      label: Text(compact ? 'Track' : 'Track Order'),
    );
  }
}
