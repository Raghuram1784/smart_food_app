import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../commerce/commerce_repository.dart';
import '../location/location_picker_screen.dart';
import 'tracking_api.dart';

/// Owner confirms the outlet's real pickup point (GPS at the counter, or by moving the map pin).
/// No restaurant coordinates are ever invented; until confirmed, tracking hides the restaurant marker.
Future<void> setPickupLocation(BuildContext context, WidgetRef ref, String restaurantId) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Set pickup location'),
      content: const Text('Stand at your pickup counter and use GPS, or move the pin to the exact entrance. Customers and riders see this point on the live map.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('pickup-continue'), onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final picked = await Navigator.of(context).push<Object?>(MaterialPageRoute(builder: (_) => const LocationPickerScreen()));
  if (picked is! PickedLocation || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(trackingApiProvider).setPickupLocation(restaurantId, picked.latitude, picked.longitude,
        accuracyMeters: picked.source == PickedLocationSource.deviceGps ? picked.accuracyMeters : null);
    messenger.showSnackBar(const SnackBar(content: Text('Pickup location saved')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(commerceError(e))));
  }
}
