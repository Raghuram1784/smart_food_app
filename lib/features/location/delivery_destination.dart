import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../commerce/commerce_repository.dart';

/// The customer's chosen saved address (by id), persisted per customer account.
/// Temporary coordinates are never persisted here — only confirmed saved addresses.
class SelectedAddressNotifier extends Notifier<String?> {
  String? _key(String? customerId) =>
      customerId == null ? null : 'delivery_address_$customerId';

  @override
  String? build() {
    final key = _key(ref.watch(customerIdProvider));
    if (key == null) return null;
    try {
      return ref.read(preferencesProvider).getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> select(String? addressId) async {
    state = addressId;
    final key = _key(ref.read(customerIdProvider));
    if (key == null) return;
    try {
      final prefs = ref.read(preferencesProvider);
      if (addressId == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, addressId);
      }
    } catch (_) {
      // Keep the in-memory selection if storage is unavailable.
    }
  }
}

final selectedAddressIdProvider =
    NotifierProvider<SelectedAddressNotifier, String?>(SelectedAddressNotifier.new);

/// The confirmed delivery destination: the selected saved address, else the
/// default saved address, else none ("Choose delivery location").
final deliveryDestinationProvider = Provider<AsyncValue<Json?>>((ref) {
  if (ref.watch(customerIdProvider) == null) return const AsyncData(null);
  final selected = ref.watch(selectedAddressIdProvider);
  return ref.watch(addressesProvider).whenData((addresses) {
    return addresses.where((a) => a['id'] == selected).firstOrNull ??
        addresses.where((a) => a['isDefault'] == true).firstOrNull;
  });
});

/// Service area of the confirmed destination (used for price previews and
/// smart search). Null when no destination or the address is outside the
/// current service areas. Never defaults to a demo locality.
final deliveryServiceAreaProvider = Provider<ServiceArea?>((ref) {
  final address = ref.watch(deliveryDestinationProvider).asData?.value;
  final id = address?['localityId'];
  if (id is! String) return null;
  final name = (address?['locality'] as Map?)?['name'];
  return ServiceArea(id, name is String ? name : id, (address?['city'] as String?) ?? '');
});

/// Short display text for a saved address, built only from its own fields.
String destinationTitle(Json a) => (a['label'] as String?)?.trim().isNotEmpty == true ? a['label'] as String : 'Delivery address';

String destinationSubtitle(Json a) {
  final parts = <String>[
    if ((a['addressLine1'] as String?)?.isNotEmpty == true) a['addressLine1'] as String,
    if ((a['locality'] as Map?)?['name'] is String) (a['locality'] as Map)['name'] as String,
    if ((a['city'] as String?)?.isNotEmpty == true) a['city'] as String,
  ];
  return parts.join(', ');
}

enum ServiceabilityStatus { serviceable, serviceableUnverifiedDistance, notServiceable }

class RestaurantServiceability {
  final String restaurantId;
  final bool eligible;
  final ServiceabilityStatus status;
  final String basis;
  final int? straightLineMeters;
  final String reason;
  const RestaurantServiceability({
    required this.restaurantId,
    required this.eligible,
    required this.status,
    required this.basis,
    required this.straightLineMeters,
    required this.reason,
  });

  factory RestaurantServiceability.fromJson(Json j) => RestaurantServiceability(
        restaurantId: j['restaurantId'] as String,
        eligible: j['eligible'] == true,
        status: switch (j['status']) {
          'SERVICEABLE' => ServiceabilityStatus.serviceable,
          'SERVICEABLE_UNVERIFIED_DISTANCE' => ServiceabilityStatus.serviceableUnverifiedDistance,
          _ => ServiceabilityStatus.notServiceable,
        },
        basis: j['basis'] as String? ?? 'NONE',
        straightLineMeters: (j['straightLineMeters'] as num?)?.toInt(),
        reason: j['reason'] as String? ?? '',
      );

  String get shortLabel => switch (status) {
        ServiceabilityStatus.serviceable =>
          'Delivers here · ${((straightLineMeters ?? 0) / 1000).toStringAsFixed(1)} km straight line',
        ServiceabilityStatus.serviceableUnverifiedDistance => 'Delivers to this area · distance not verified',
        ServiceabilityStatus.notServiceable => 'Doesn\'t deliver to this address',
      };
}

/// Server-evaluated delivery eligibility of every restaurant for the confirmed
/// destination. Null when no destination is chosen.
final serviceabilityProvider =
    FutureProvider.autoDispose<Map<String, RestaurantServiceability>?>((ref) async {
  final destination = ref.watch(deliveryDestinationProvider).asData?.value;
  final id = destination?['id'];
  if (id is! String) return null;
  final raw = await ref.watch(commerceRepositoryProvider).request('GET', 'addresses/$id/serviceability');
  final list = (raw as Map)['restaurants'] as List? ?? const [];
  return {
    for (final r in list)
      (r as Map)['restaurantId'] as String: RestaurantServiceability.fromJson(Json.from(r)),
  };
});
