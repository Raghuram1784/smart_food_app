import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_repository.dart';
import '../location/location_picker_screen.dart';
import 'commerce_repository.dart';

/// Short "Add delivery address" form used at checkout. Asks only what a rider
/// needs; the area is chosen from the configured service areas (or "Other",
/// which is saved but cannot be delivered to yet). A map pin is optional.
class QuickAddressForm extends ConsumerStatefulWidget {
  final bool makeDefault;
  final ValueChanged<Json> onSaved;
  final VoidCallback? onCancel;
  const QuickAddressForm({super.key, required this.onSaved, this.makeDefault = true, this.onCancel});

  @override
  ConsumerState<QuickAddressForm> createState() => _QuickAddressFormState();
}

class _QuickAddressFormState extends ConsumerState<QuickAddressForm> {
  static const _other = '__other__';
  final _form = GlobalKey<FormState>();
  final _c = {for (final k in ['recipient', 'phone', 'house', 'street', 'landmark', 'pincode']) k: TextEditingController()};
  String? _area;
  PickedLocation? _pin;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPin() async {
    final picked = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (picked is PickedLocation && mounted) setState(() => _pin = picked);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final areas = ref.read(areasProvider).asData?.value ?? const [];
    final area = areas.where((a) => a.id == _area).firstOrNull;
    try {
      final saved = await ref.read(commerceRepositoryProvider).request('POST', 'addresses', {
        'label': 'Home',
        'recipientName': _c['recipient']!.text.trim(),
        'contactNumber': _c['phone']!.text.trim(),
        'addressLine1': '${_c['house']!.text.trim()}, ${_c['street']!.text.trim()}',
        'addressLine2': '',
        'landmark': _c['landmark']!.text.trim(),
        'city': area?.city ?? '',
        'localityId': _area == _other ? null : _area,
        'postalCode': _c['pincode']!.text.trim(),
        'isDefault': widget.makeDefault,
        'latitude': _pin?.latitude,
        'longitude': _pin?.longitude,
        'locationAccuracyMeters': _pin?.source == PickedLocationSource.deviceGps ? _pin?.accuracyMeters : null,
        'locationSource': _pin?.source.api,
      });
      if (mounted) widget.onSaved(Json.from(saved as Map));
    } catch (e) {
      if (mounted) setState(() => _error = commerceError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint, counterText: '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final areas = ref.watch(areasProvider);
    String? required(String? v, [int min = 1]) => (v?.trim().length ?? 0) < min ? 'Required' : null;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add delivery address', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Saved for your next orders.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          TextFormField(key: const ValueKey('qa-recipient'), controller: _c['recipient'], enabled: !_busy, maxLength: 80, decoration: _dec('Recipient name'), validator: (v) => required(v, 2)),
          TextFormField(
            key: const ValueKey('qa-phone'),
            controller: _c['phone'],
            enabled: !_busy,
            maxLength: 13,
            keyboardType: TextInputType.phone,
            decoration: _dec('Phone number'),
            validator: (v) => RegExp(r'^(?:\+91)?[6-9][0-9]{9}$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid Indian mobile number',
          ),
          TextFormField(key: const ValueKey('qa-house'), controller: _c['house'], enabled: !_busy, maxLength: 60, decoration: _dec('Flat / house number'), validator: required),
          TextFormField(key: const ValueKey('qa-street'), controller: _c['street'], enabled: !_busy, maxLength: 120, decoration: _dec('Street or building'), validator: (v) => required(v, 3)),
          DropdownButtonFormField<String>(
            key: const ValueKey('qa-area'),
            initialValue: _area,
            isExpanded: true,
            decoration: _dec('Area / locality'),
            items: [
              for (final a in areas.asData?.value ?? const [])
                DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: _other, child: Text('Other area (not delivered to yet)', overflow: TextOverflow.ellipsis)),
            ],
            validator: (v) => v == null ? 'Choose your area' : null,
            onChanged: _busy ? null : (v) => setState(() => _area = v),
          ),
          if (_area == _other)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('We can save this address, but restaurants do not deliver outside the listed areas yet.', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('qa-pincode'),
            controller: _c['pincode'],
            enabled: !_busy,
            maxLength: 6,
            keyboardType: TextInputType.number,
            decoration: _dec('Pincode'),
            validator: (v) => RegExp(r'^[1-9][0-9]{5}$').hasMatch(v?.trim() ?? '') ? null : 'Enter a 6-digit pincode',
          ),
          TextFormField(key: const ValueKey('qa-landmark'), controller: _c['landmark'], enabled: !_busy, maxLength: 120, decoration: _dec('Landmark (optional)')),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _pickPin,
              icon: Icon(_pin == null ? Icons.add_location_alt_outlined : Icons.check_circle_outline),
              label: Text(_pin == null ? 'Pin on map (optional)' : 'Map pin added'),
            ),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (widget.onCancel != null) ...[
                Expanded(child: OutlinedButton(onPressed: _busy ? null : widget.onCancel, child: const Text('Cancel'))),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const ValueKey('qa-save'),
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Save address'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
