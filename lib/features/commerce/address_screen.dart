import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:latlong2/latlong.dart';

import '../catalog/catalog_repository.dart';
import '../location/delivery_destination.dart';
import '../location/location_picker_screen.dart';
import 'commerce_repository.dart';
import 'commerce_widgets.dart';

class AddressScreen extends ConsumerStatefulWidget {
  const AddressScreen({super.key});
  @override
  ConsumerState<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends ConsumerState<AddressScreen> {
  bool busy = false;
  String? error;
  Future<void> edit([Json? address]) async {
    final result = await Navigator.of(context).push<Json?>(
      MaterialPageRoute(
        builder: (_) => CommerceGate(child: AddressEditor(address: address)),
      ),
    );
    if (mounted && result != null) ref.invalidate(addressesProvider);
  }

  Future<void> remove(Json address) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this address?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep address'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref
          .read(commerceRepositoryProvider)
          .request('DELETE', 'addresses/${address['id']}');
      if (ref.read(selectedAddressIdProvider) == address['id']) {
        await ref.read(selectedAddressIdProvider.notifier).select(null);
      }
      ref.invalidate(addressesProvider);
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Delivery addresses')),
    body: ref
        .watch(addressesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              CommerceFailure(e, () => ref.invalidate(addressesProvider)),
          data: (addresses) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (error != null) Text(error!),
              if (addresses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Save an address to complete your checkout.'),
                ),
              for (final address in addresses)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${address['label']}${address['isDefault'] ? ' · Default' : ''}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${address['recipientName']}\n${destinationSubtitle(address)} ${address['postalCode']}',
                        ),
                        Text(
                          [
                            address['hasConfirmedLocation'] == true
                                ? (address['locationSource'] == 'DEVICE_GPS'
                                      ? 'Map pin from device GPS'
                                      : 'Map pin placed by you')
                                : 'No map pin · delivery distance can\'t be verified',
                            if (address['localityId'] == null)
                              'Outside current service areas',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: busy ? null : () => edit(address),
                              child: const Text('Edit / set default'),
                            ),
                            TextButton(
                              onPressed: busy ? null : () => remove(address),
                              child: const Text('Remove address'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: busy ? null : () => edit(),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add address'),
              ),
            ],
          ),
        ),
  );
}

class AddressEditor extends ConsumerStatefulWidget {
  final Json? address;

  /// Point the customer just confirmed on the map (new or moved pin).
  final PickedLocation? location;
  const AddressEditor({super.key, this.address, this.location});
  @override
  ConsumerState<AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends ConsumerState<AddressEditor> {
  static const _notListed = '__not_listed__';
  final form = GlobalKey<FormState>();
  late final fields = {
    for (final key in [
      'label',
      'recipientName',
      'contactNumber',
      'addressLine1',
      'addressLine2',
      'landmark',
      'city',
      'postalCode',
    ])
      key: TextEditingController(text: widget.address?[key] as String? ?? ''),
  };
  // Explicit choice; no default from any demo locality. Null = not chosen yet.
  late String? area = widget.address == null
      ? null
      : (widget.address!['localityId'] as String? ?? _notListed);
  late bool isDefault = widget.address?['isDefault'] ?? true;
  double? latitude, longitude, accuracy;
  String? source;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final loc = widget.location;
    if (loc != null) {
      _applyPicked(loc);
    } else if (widget.address?['latitude'] != null) {
      latitude = (widget.address!['latitude'] as num).toDouble();
      longitude = (widget.address!['longitude'] as num).toDouble();
      accuracy = (widget.address!['locationAccuracyMeters'] as num?)
          ?.toDouble();
      source = widget.address!['locationSource'] as String?;
    }
  }

  void _applyPicked(PickedLocation loc) {
    latitude = loc.latitude;
    longitude = loc.longitude;
    accuracy = loc.accuracyMeters;
    source = loc.source.api;
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final start = latitude != null ? LatLng(latitude!, longitude!) : null;
    final picked = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialPoint: start,
          startWithGps: start == null,
        ),
      ),
    );
    if (picked is PickedLocation && mounted) {
      setState(() => _applyPicked(picked));
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final saved = await ref.read(commerceRepositoryProvider).request(
        widget.address == null ? 'POST' : 'PATCH',
        widget.address == null
            ? 'addresses'
            : 'addresses/${widget.address!['id']}',
        {
          for (final e in fields.entries) e.key: e.value.text.trim(),
          'localityId': area == _notListed ? null : area,
          'isDefault': isDefault,
          'latitude': latitude,
          'longitude': longitude,
          'locationAccuracyMeters': source == 'DEVICE_GPS' ? accuracy : null,
          'locationSource': latitude == null ? null : source,
        },
      );
      if (mounted) Navigator.pop(context, Json.from(saved as Map));
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final areas = ref.watch(areasProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.address == null ? 'Add address' : 'Edit address'),
      ),
      // Non-lazy scroll view: every field stays mounted, so Form.validate()
      // checks all of them even when scrolled out of view.
      body: Form(
        key: form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            latitude != null
                                ? Icons.place
                                : Icons.location_off_outlined,
                            color: latitude != null
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              latitude != null
                                  ? 'Delivery point confirmed on map'
                                  : 'No map pin',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        latitude != null
                            ? '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)} · '
                                  '${source == 'DEVICE_GPS' ? 'device GPS${accuracy != null ? ' ±${accuracy!.round()} m' : ''}' : 'placed by you'}'
                            : 'Without a map pin, delivery distance can\'t be verified. Address lookup from the pin is not available, so please type the address below.',
                        key: const ValueKey('address-location-summary'),
                        style: theme.textTheme.bodySmall,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: busy ? null : _pickOnMap,
                            icon: const Icon(Icons.map_outlined),
                            label: Text(
                              latitude != null
                                  ? 'Change on map'
                                  : 'Add map pin',
                            ),
                          ),
                          if (latitude != null)
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                      latitude = longitude = accuracy = null;
                                      source = null;
                                    }),
                              child: const Text('Remove pin'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              for (final entry in {
                'label': 'Address label (Home, Work…)',
                'recipientName': 'Recipient name',
                'contactNumber': 'Mobile number',
                'addressLine1': 'House / flat no., building, street',
                'addressLine2': 'Area / street (optional)',
                'landmark': 'Landmark (optional)',
                'city': 'City',
                'postalCode': 'Postal code',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    key: ValueKey('address-${entry.key}'),
                    controller: fields[entry.key],
                    enabled: !busy,
                    maxLength: switch (entry.key) {
                      'addressLine1' || 'addressLine2' => 200,
                      'landmark' => 120,
                      'recipientName' || 'city' => 80,
                      'contactNumber' => 13,
                      'postalCode' => 6,
                      _ => 40,
                    },
                    keyboardType:
                        ['contactNumber', 'postalCode'].contains(entry.key)
                        ? TextInputType.phone
                        : TextInputType.streetAddress,
                    decoration: InputDecoration(
                      labelText: entry.value,
                      counterText: '',
                    ),
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (['addressLine2', 'landmark'].contains(entry.key)) {
                        return null;
                      }
                      if (entry.key == 'contactNumber' &&
                          !RegExp(r'^(?:\+91)?[6-9][0-9]{9}$')
                              .hasMatch(value)) {
                        return 'Enter a valid Indian mobile number.';
                      }
                      if (entry.key == 'postalCode' &&
                          !RegExp(r'^[1-9][0-9]{5}$').hasMatch(value)) {
                        return 'Enter a six-digit postal code.';
                      }
                      if (value.length <
                          (entry.key == 'addressLine1'
                              ? 5
                              : entry.key == 'recipientName'
                              ? 2
                              : 1)) {
                        return 'Please complete this field.';
                      }
                      return null;
                    },
                  ),
                ),
              DropdownButtonFormField<String>(
                key: const ValueKey('address-service-area'),
                initialValue: area,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Delivery service area',
                  helperText: 'Choose the area this address is in. We don\'t guess it from GPS.',
                  helperMaxLines: 2,
                ),
                items: [
                  for (final a in areas.asData?.value ?? const [])
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name, overflow: TextOverflow.ellipsis),
                    ),
                  // Keep the address's current area selectable while areas load or if it
                  // is no longer listed; DropdownButton requires the value to be present.
                  if (area != null &&
                      area != _notListed &&
                      !(areas.asData?.value ?? const []).any(
                        (a) => a.id == area,
                      ))
                    DropdownMenuItem(
                      value: area,
                      child: Text(
                        (widget.address?['locality'] as Map?)?['name']
                                as String? ??
                            area!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const DropdownMenuItem(
                    value: _notListed,
                    child: Text(
                      'Not listed — outside current service areas',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                validator: (v) => v == null
                    ? 'Choose a service area, or "Not listed".'
                    : null,
                onChanged: busy ? null : (v) => setState(() => area = v),
              ),
              if (areas.hasError)
                TextButton(
                  onPressed: () => ref.invalidate(areasProvider),
                  child: const Text('Could not load service areas. Retry'),
                ),
              if (area == _notListed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Restaurants can\'t deliver to addresses outside the current service areas yet. You can still save it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use as default address'),
                value: isDefault,
                onChanged: busy ? null : (v) => setState(() => isDefault = v),
              ),
              if (error != null)
                Text(error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Saving…' : 'Save address'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
