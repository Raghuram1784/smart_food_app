import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../commerce/address_screen.dart';
import '../commerce/commerce_repository.dart';
import '../commerce/commerce_widgets.dart';
import 'delivery_destination.dart';
import 'location_picker_screen.dart';

/// Start a new delivery destination: map/GPS → address details → save → select.
/// Nothing is saved unless the customer confirms the address form.
Future<void> addDeliveryDestination(
  BuildContext context,
  WidgetRef ref, {
  required bool useCurrentLocation,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final current = ref.read(deliveryDestinationProvider).asData?.value;
  final lat = (current?['latitude'] as num?)?.toDouble();
  final lng = (current?['longitude'] as num?)?.toDouble();
  final start = !useCurrentLocation && lat != null && lng != null ? LatLng(lat, lng) : null;

  final picked = await navigator.push<Object?>(
    MaterialPageRoute(
      builder: (_) => LocationPickerScreen(
        initialPoint: start,
        startWithGps: useCurrentLocation || start == null,
      ),
    ),
  );
  if (picked == null || !navigator.mounted) return; // cancelled: nothing changes
  final saved = await navigator.push<Json?>(
    MaterialPageRoute(
      builder: (_) => CommerceGate(
        child: AddressEditor(location: picked is PickedLocation ? picked : null),
      ),
    ),
  );
  if (saved == null) return;
  ref.invalidate(addressesProvider);
  await ref.read(selectedAddressIdProvider.notifier).select(saved['id'] as String);
}

Future<void> showDeliveryLocationSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Opened from the forest header, whose theme forces light text; render with the app theme.
    builder: (sheetContext) => Theme(
      data: Theme.of(Navigator.of(context, rootNavigator: true).context),
      child: _DeliveryLocationSheet(parentContext: context),
    ),
  );
}

class _DeliveryLocationSheet extends ConsumerWidget {
  final BuildContext parentContext;
  const _DeliveryLocationSheet({required this.parentContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final addresses = ref.watch(addressesProvider);
    final selected = ref.watch(deliveryDestinationProvider).asData?.value;
    void start(bool gps) {
      Navigator.pop(context);
      addDeliveryDestination(parentContext, ref, useCurrentLocation: gps);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text('Deliver to', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          ListTile(
            key: const ValueKey('use-current-location'),
            leading: const Icon(Icons.my_location),
            title: const Text('Use current location'),
            subtitle: const Text('Uses this phone\'s GPS, then you confirm the pin'),
            onTap: () => start(true),
          ),
          ListTile(
            key: const ValueKey('choose-on-map'),
            leading: const Icon(Icons.map_outlined),
            title: const Text('Choose on map'),
            subtitle: const Text('Deliver somewhere else, e.g. to family'),
            onTap: () => start(false),
          ),
          const Divider(height: 24),
          Text('Saved addresses', style: theme.textTheme.titleSmall),
          addresses.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => CommerceFailure(e, () => ref.invalidate(addressesProvider)),
            data: (list) => Column(
              children: [
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No saved addresses yet.'),
                  ),
                for (final a in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      selected?['id'] == a['id'] ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: selected?['id'] == a['id'] ? theme.colorScheme.primary : null,
                    ),
                    title: Text(destinationTitle(a)),
                    subtitle: Text(
                      [
                        destinationSubtitle(a),
                        if (a['hasConfirmedLocation'] != true) 'No map pin · distance can\'t be verified',
                        if (a['localityId'] == null) 'Outside current service areas',
                      ].where((s) => s.isNotEmpty).join('\n'),
                    ),
                    onTap: () async {
                      await ref.read(selectedAddressIdProvider.notifier).select(a['id'] as String);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.edit_location_alt_outlined),
            label: const Text('Manage saved addresses'),
            onPressed: () {
              Navigator.pop(context);
              parentContext.push('/addresses');
            },
          ),
        ],
      ),
    );
  }
}

/// "Deliver to" header for Home. Shows only the actual confirmed destination.
class DeliveryLocationBar extends ConsumerWidget {
  const DeliveryLocationBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final destination = ref.watch(deliveryDestinationProvider);
    final signedIn = ref.watch(customerIdProvider) != null;
    final address = destination.asData?.value;
    final title = !signedIn
        ? 'Sign in to set a delivery location'
        : destination.isLoading
            ? 'Loading your addresses…'
            : address == null
                ? 'Choose delivery address'
                : _localityTitle(address) ?? destinationTitle(address);
    // Header shows the locality cleanly; the full address stays in Cart/Checkout.
    final city = (address?['city'] as String?)?.trim() ?? '';
    final subtitle = address == null
        ? null
        : _localityTitle(address) != null
            ? (city.isEmpty ? null : city.split(RegExp(r'\s+')).map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' '))
            : destinationSubtitle(address);
    return InkWell(
      key: const ValueKey('deliver-to'),
      borderRadius: BorderRadius.circular(12),
      onTap: signedIn ? () => showDeliveryLocationSheet(context, ref) : () => context.push('/login'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DELIVER TO', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1)),
            const SizedBox(height: 3),
            Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
            if (subtitle != null && subtitle.isNotEmpty)
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Inline prompt used where a confirmed destination is required.
class ChooseDestinationPrompt extends ConsumerWidget {
  final String message;
  final bool compact;
  const ChooseDestinationPrompt({super.key, required this.message, this.compact = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (!compact) ...[
          Icon(Icons.location_searching, size: 36, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
        ],
        Text(message, textAlign: compact ? TextAlign.start : TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.place_outlined),
          label: const Text('Choose delivery location'),
          onPressed: ref.watch(customerIdProvider) == null
              ? () => context.push('/login')
              : () => showDeliveryLocationSheet(context, ref),
        ),
      ],
    );
    return compact ? body : Center(child: Padding(padding: const EdgeInsets.all(28), child: body));
  }
}

/// Per-restaurant delivery eligibility for the confirmed destination.
class ServiceabilityBadge extends ConsumerWidget {
  final String restaurantId;
  final bool showReason;
  const ServiceabilityBadge(this.restaurantId, {super.key, this.showReason = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final destination = ref.watch(deliveryDestinationProvider).asData?.value;
    if (destination == null) {
      return _chip(theme, Icons.place_outlined, 'Choose a location to check delivery', theme.colorScheme.outline);
    }
    return ref.watch(serviceabilityProvider).when(
          loading: () => _chip(theme, Icons.more_horiz, 'Checking delivery…', theme.colorScheme.outline),
          error: (_, _) => _chip(theme, Icons.error_outline, 'Delivery check unavailable', theme.colorScheme.outline),
          data: (map) {
            final s = map?[restaurantId];
            if (s == null) return const SizedBox.shrink();
            final color = switch (s.status) {
              ServiceabilityStatus.serviceable => Colors.green.shade700,
              ServiceabilityStatus.serviceableUnverifiedDistance => Colors.amber.shade800,
              ServiceabilityStatus.notServiceable => theme.colorScheme.error,
            };
            final icon = s.eligible ? Icons.delivery_dining : Icons.block;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _chip(theme, icon, s.shortLabel, color),
                if (showReason)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(s.reason, style: theme.textTheme.bodySmall),
                  ),
              ],
            );
          },
        );
  }

  Widget _chip(ThemeData theme, IconData icon, String text, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

/// "Kukatpally / KPHB" from a saved address's service locality, or null when it has none.
String? _localityTitle(Map<String, dynamic> address) {
  final name = (address['locality'] as Map?)?['name'];
  if (name is! String || name.trim().isEmpty) return null;
  return name.split(',').first.trim();
}
