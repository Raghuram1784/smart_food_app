import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
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
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CommerceGate(child: AddressEditor(address: address)),
      ),
    );
    if (mounted && result == true) ref.invalidate(addressesProvider);
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
                          '${address['recipientName']}\n${address['addressLine1']}\n${address['locality']?['name'] ?? address['localityId']} ${address['postalCode']}',
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
  const AddressEditor({super.key, this.address});
  @override
  ConsumerState<AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends ConsumerState<AddressEditor> {
  final form = GlobalKey<FormState>();
  late final fields = {
    for (final key in [
      'label',
      'recipientName',
      'contactNumber',
      'addressLine1',
      'addressLine2',
      'landmark',
      'postalCode',
    ])
      key: TextEditingController(text: widget.address?[key] ?? ''),
  };
  late String area =
      widget.address?['localityId'] ?? ref.read(locationProvider).id;
  late bool isDefault = widget.address?['isDefault'] ?? true;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await ref.read(commerceRepositoryProvider).request(
        widget.address == null ? 'POST' : 'PATCH',
        widget.address == null
            ? 'addresses'
            : 'addresses/${widget.address!['id']}',
        {
          for (final e in fields.entries) e.key: e.value.text.trim(),
          'localityId': area,
          'isDefault': isDefault,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.address == null ? 'Add address' : 'Edit address'),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final entry in {
            'label': 'Address label',
            'recipientName': 'Recipient name',
            'contactNumber': 'Mobile number',
            'addressLine1': 'House / street address',
            'addressLine2': 'Address line 2 (optional)',
            'landmark': 'Landmark (optional)',
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
                  'recipientName' => 80,
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
                      !RegExp(r'^(?:\+91)?[6-9][0-9]{9}$').hasMatch(value)) {
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
            initialValue: area,
            decoration: const InputDecoration(labelText: 'Locality'),
            items: [
              for (final a in ServiceArea.hyderabadAreas)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: busy ? null : (v) => setState(() => area = v!),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use as default address'),
            value: isDefault,
            onChanged: busy ? null : (v) => setState(() => isDefault = v),
          ),
          const Text(
            'We check the selected locality with the restaurant. GPS and exact route verification are not available yet.',
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : 'Save address'),
          ),
        ],
      ),
    ),
  );
}
