import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog.dart';
import '../../shared/components.dart';
import 'commerce_repository.dart';
import 'commerce_widgets.dart';
import 'quick_address_form.dart';
import '../location/delivery_destination.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});
  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool busy = false;
  bool quoting = false;
  String? error, quoteError, addressId, _lastQuoteKey, _quotedAddressId;
  Json? quote;

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> mutate(String method, String path, Json data) => action(
    () async {
      setState(() {
        quote = null;
        quoteError = null;
        _lastQuoteKey = null;
        _quotedAddressId = null;
      });
      try {
        await ref.read(commerceRepositoryProvider).request(method, path, data);
      } finally {
        if (mounted) ref.invalidate(cartProvider);
      }
    },
  );

  Future<void> fetchQuote(Json cart, Json address, {bool force = false}) async {
    final key = '${cart['version']}:${address['id']}';
    if (quoting) return;
    if (!force && _lastQuoteKey == key) return;
    setState(() {
      quoting = true;
      quoteError = null;
      _lastQuoteKey = key;
    });
    try {
      final result = Json.from(
        await ref.read(commerceRepositoryProvider).request(
          'POST',
          'cart/quote',
          {'addressId': address['id'], 'expectedVersion': cart['version']},
        ),
      );
      if (mounted) {
        setState(() {
          quote = result;
          _quotedAddressId = address['id'] as String?;
          quoteError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          quote = null;
          _quotedAddressId = null;
          quoteError = commerceError(e);
        });
      }
    } finally {
      if (mounted) setState(() => quoting = false);
    }
  }

  Future<void> resume(Json input) => action(() async {
    final id = ref.read(customerIdProvider)!;
    final repo = ref.read(commerceRepositoryProvider);
    try {
      final order = await repo.place(id, input);
      if (!mounted) return;
      ref.invalidate(cartProvider);
      ref.invalidate(pendingCheckoutProvider);
      if (mounted) context.go('/orders/${order['id']}?placed=true');
    } on DioException catch (e) {
      if (e.response?.statusCode == 409 ||
          e.response?.statusCode == 422 ||
          e.response?.statusCode == 404) {
        await repo.forgetPending(id);
        if (mounted) ref.invalidate(pendingCheckoutProvider);
      }
      rethrow;
    }
  });

  Future<void> confirmClear(Json cart) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear your cart?'),
        content: const Text(
          'All selected meals and customizations will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep meals'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear cart'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await mutate('DELETE', 'cart', {'expectedVersion': cart['version']});
    }
  }

  Future<void> openAddresses() async {
    await context.push('/addresses');
    if (!mounted) return;
    setState(() {
      quote = null;
      quoteError = null;
      _lastQuoteKey = null;
      _quotedAddressId = null;
    });
    ref.invalidate(addressesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final saved = ref.watch(addressesProvider);
    final pending = ref.watch(pendingCheckoutProvider).asData?.value;
    final cartAsync = ref.watch(cartProvider);

    final cart = cartAsync.asData?.value;
    final items = (cart?['items'] as List?) ?? const [];
    final addresses = saved.asData?.value ?? const [];
    // Checkout uses the confirmed delivery destination (never the phone's
    // current position). Choosing another address here updates it app-wide.
    final destination = ref.watch(deliveryDestinationProvider).asData?.value;
    final chosen =
        addresses.where((a) => a['id'] == addressId).firstOrNull ??
        addresses.where((a) => a['id'] == destination?['id']).firstOrNull ??
        addresses.firstOrNull;
    final quoteValid =
        cart != null &&
        chosen != null &&
        quote != null &&
        quote!['cartVersion'] == cart['version'] &&
        (quote!['addressId'] ?? _quotedAddressId) == chosen['id'];

    if (cart != null && items.isNotEmpty && chosen != null && !busy) {
      final expectedKey = '${cart['version']}:${chosen['id']}';
      if (_lastQuoteKey != expectedKey && !quoting) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) fetchQuote(cart, chosen);
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your cart'),
        actions: [
          IconButton(
            tooltip: 'Order history',
            onPressed: () => context.push('/orders'),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: cartAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => CommerceFailure(e, () => ref.invalidate(cartProvider)),
        data: (data) {
          if (data == null) return const SizedBox();
          final lines = data['items'] as List;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              if (pending != null) ...[
                _CartNoticeCard(
                  icon: Icons.sync_problem_outlined,
                  title: 'Previous checkout needs verification',
                  message: 'Check the previous attempt before submitting a duplicate order.',
                  actionLabel: 'Check previous checkout',
                  onPressed: busy ? null : () => resume(pending),
                ),
                const SizedBox(height: 12),
              ],
              if (error != null) ...[
                _CartNoticeCard(
                  icon: Icons.error_outline,
                  title: 'Action could not finish',
                  message: error!,
                  isError: true,
                ),
                const SizedBox(height: 12),
              ],
              if (lines.isEmpty) ...[
                const SizedBox(height: 48),
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 52,
                  color: scheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Something delicious\nbelongs here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Your saved meals will appear here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: FilledButton.tonal(
                    onPressed: () => context.go('/'),
                    child: const Text('Explore kitchens'),
                  ),
                ),
              ] else ...[
                _CartRestaurantHeader(
                  restaurantName: data['restaurant']['name'] as String,
                  itemCount: lines.fold<int>(
                    0,
                    (sum, line) => sum + (line['quantity'] as int),
                  ),
                  onBrowseMenu: data['restaurant']['id'] == null
                      ? null
                      : () => context.push(
                          '/restaurant/${data['restaurant']['id']}',
                        ),
                  onClearCart: busy ? null : () => confirmClear(data),
                ),
                const SizedBox(height: 12),
                for (final line in lines) ...[
                  _CartItemCard(
                    line: Json.from(line),
                    restaurantName: data['restaurant']['name'] as String,
                    busy: busy,
                    onDecrease: (line['quantity'] as int) <= 1
                        ? null
                        : () => mutate('PATCH', 'cart/items/${line['id']}', {
                            'expectedVersion': data['version'],
                            'quantity': (line['quantity'] as int) - 1,
                          }),
                    onIncrease: (line['quantity'] as int) >= 20
                        ? null
                        : () => mutate('PATCH', 'cart/items/${line['id']}', {
                            'expectedVersion': data['version'],
                            'quantity': (line['quantity'] as int) + 1,
                          }),
                    onRemove: () => mutate(
                      'DELETE',
                      'cart/items/${line['id']}',
                      {'expectedVersion': data['version']},
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                _DeliveryAddressCard(
                  addresses: addresses,
                  chosen: chosen,
                  isLoading: saved.isLoading,
                  error: saved.hasError ? saved.error : null,
                  busy: busy,
                  onRetryAddresses: () => ref.invalidate(addressesProvider),
                  onSelectAddress: (id) => setState(() {
                    ref.read(selectedAddressIdProvider.notifier).select(id);
                    addressId = id;
                    quote = null;
                    quoteError = null;
                    _lastQuoteKey = null;
                    _quotedAddressId = null;
                  }),
                  onManageAddresses: openAddresses,
                  onAddressSaved: (saved) {
                    ref.invalidate(addressesProvider);
                    ref.read(selectedAddressIdProvider.notifier).select(saved['id'] as String);
                    setState(() {
                      addressId = saved['id'] as String;
                      quote = null;
                      quoteError = null;
                      _lastQuoteKey = null;
                      _quotedAddressId = null;
                    });
                  },
                ),
                const SizedBox(height: 14),
                // With no address, the inline address form above is the call to action.
                if (chosen == null)
                  const SizedBox.shrink()
                else if (quoting && !quoteValid)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Calculating live server bill for ${chosen['locality']?['name'] ?? chosen['label']}…',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (quoteError != null)
                  _CartNoticeCard(
                    icon: Icons.info_outline_rounded,
                    title: 'Checkout unavailable for this address',
                    message: quoteError!,
                    isError: true,
                    actionLabel: 'Change address',
                    secondaryActionLabel: 'Refresh bill',
                    onPressed: busy ? null : openAddresses,
                    onSecondaryPressed: busy
                        ? null
                        : () => fetchQuote(data, chosen, force: true),
                  )
                else if (quoteValid)
                  OrderBill(
                    quote!,
                    title: 'Bill summary',
                    onRefresh: busy || quoting
                        ? null
                        : () => fetchQuote(data, chosen, force: true),
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: busy || quoting
                          ? null
                          : () => fetchQuote(data, chosen, force: true),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh bill'),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: items.isEmpty
          ? null
          : _StickyCheckoutBar(
              chosen: chosen,
              pending: pending,
              quote: quoteValid ? quote : null,
              cart: cart,
              quoting: quoting,
              busy: busy,
              quoteError: quoteError,
              onChooseAddress: openAddresses,
              onReviewOrder: () => context.push(
                '/checkout',
                extra: {...quote!, 'addressId': chosen!['id']},
              ),
              onResumePending: () => resume(pending!),
              onRetryQuote: chosen == null || cart == null
                  ? null
                  : () => fetchQuote(cart, chosen, force: true),
            ),
    );
  }
}

class _CartRestaurantHeader extends StatelessWidget {
  final String restaurantName;
  final int itemCount;
  final VoidCallback? onBrowseMenu;
  final VoidCallback? onClearCart;
  const _CartRestaurantHeader({
    required this.restaurantName,
    required this.itemCount,
    this.onBrowseMenu,
    this.onClearCart,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurantName,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (onBrowseMenu != null)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onBrowseMenu,
              child: const Text('Menu'),
            ),
          if (onClearCart != null)
            IconButton(
              tooltip: 'Clear cart',
              visualDensity: VisualDensity.compact,
              onPressed: onClearCart,
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            ),
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final Json line;
  final String restaurantName;
  final bool busy;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final VoidCallback onRemove;
  const _CartItemCard({
    required this.line,
    required this.restaurantName,
    required this.busy,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final menuItem = Json.from(line['menuItem'] as Map);
    final dishName = menuItem['name'] as String;
    final variantName = line['variant']?['name'] as String?;
    final addOnNames = [
      for (final a in (line['addOns'] as List? ?? const []))
        a['addOn']?['name'] as String? ?? a['name'] as String?,
    ].whereType<String>().toList();
    final unitPaise = line['unitPricePaise'] as int?;
    final lineTotalPaise = line['lineTotalPaise'] as int?;
    final photoKey = Dish.photoKeyFor(
      (menuItem['imageKey'] as String?) ?? 'dosa',
      dishName,
    );

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FoodPhoto(photoKey, height: 68, width: 68),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dishName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        restaurantName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (variantName != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          variantName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (addOnNames.isNotEmpty)
                        Text(
                          addOnNames.join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      if (unitPaise != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '₹${formatPaise(unitPaise)} each',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Decrease $dishName',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 38,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: busy ? null : onDecrease,
                        icon: const Icon(Icons.remove, size: 18),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '${line['quantity']}',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Increase $dishName',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 38,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: busy ? null : onIncrease,
                        icon: const Icon(Icons.add, size: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.error,
                  ),
                  onPressed: busy ? null : onRemove,
                  child: const Text('Remove'),
                ),
                const Spacer(),
                if (lineTotalPaise != null)
                  Text(
                    '₹${formatPaise(lineTotalPaise)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkout address: a compact "Delivering to" summary for returning customers,
/// or a short inline form the first time. Never shown before checkout.
class _DeliveryAddressCard extends StatelessWidget {
  final List<Json> addresses;
  final Json? chosen;
  final bool isLoading;
  final Object? error;
  final bool busy;
  final VoidCallback onRetryAddresses;
  final ValueChanged<String> onSelectAddress;
  final ValueChanged<Json> onAddressSaved;
  final VoidCallback onManageAddresses;
  const _DeliveryAddressCard({
    required this.addresses,
    required this.chosen,
    required this.isLoading,
    required this.error,
    required this.busy,
    required this.onRetryAddresses,
    required this.onSelectAddress,
    required this.onAddressSaved,
    required this.onManageAddresses,
  });

  Future<void> _change(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => _AddressPickerSheet(
      addresses: addresses,
      chosenId: chosen?['id'] as String?,
      onSelect: (id) {
        Navigator.pop(sheet);
        onSelectAddress(id);
      },
      onSaved: (a) {
        Navigator.pop(sheet);
        onAddressSaved(a);
      },
      onManage: () {
        Navigator.pop(sheet);
        onManageAddresses();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = chosen;
    return Material(
      key: const ValueKey('checkout-address'),
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoading) const LinearProgressIndicator(),
            if (error != null) CommerceFailure(error!, onRetryAddresses),
            if (a != null) ...[
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Delivering to ${a['label']}',
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => _change(context),
                    child: const Text('Change'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  [
                    a['recipientName'],
                    [a['addressLine1'], if ((a['addressLine2'] as String?)?.isNotEmpty == true) a['addressLine2']].join(', '),
                    [if (a['locality']?['name'] != null) a['locality']['name'], a['postalCode']].join(' '),
                  ].join('\n'),
                  style: theme.textTheme.bodySmall,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (a['localityId'] == null)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 6),
                  child: Text(
                    'This address is outside the current delivery areas. Choose another address to order.',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
            ] else if (!isLoading && error == null)
              QuickAddressForm(makeDefault: true, onSaved: onAddressSaved),
          ],
        ),
      ),
    );
  }
}

class _AddressPickerSheet extends StatefulWidget {
  final List<Json> addresses;
  final String? chosenId;
  final ValueChanged<String> onSelect;
  final ValueChanged<Json> onSaved;
  final VoidCallback onManage;
  const _AddressPickerSheet({required this.addresses, required this.chosenId, required this.onSelect, required this.onSaved, required this.onManage});
  @override
  State<_AddressPickerSheet> createState() => _AddressPickerSheetState();
}

class _AddressPickerSheetState extends State<_AddressPickerSheet> {
  bool adding = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: adding
            ? QuickAddressForm(makeDefault: false, onSaved: widget.onSaved, onCancel: () => setState(() => adding = false))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Deliver to', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  for (final a in widget.addresses)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(a['id'] == widget.chosenId ? Icons.radio_button_checked : Icons.radio_button_off),
                      title: Text('${a['label']}'),
                      subtitle: Text('${a['addressLine1']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => widget.onSelect(a['id'] as String),
                    ),
                  TextButton.icon(onPressed: () => setState(() => adding = true), icon: const Icon(Icons.add), label: const Text('Add new address')),
                  TextButton(onPressed: widget.onManage, child: const Text('Manage saved addresses')),
                ],
              ),
      ),
    );
  }
}

class _CartNoticeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool isError;
  final String? actionLabel;
  final String? secondaryActionLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onSecondaryPressed;
  const _CartNoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
    this.actionLabel,
    this.secondaryActionLabel,
    this.onPressed,
    this.onSecondaryPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: isError ? scheme.errorContainer : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isError
              ? scheme.error.withValues(alpha: .35)
              : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isError ? scheme.onErrorContainer : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isError ? scheme.onErrorContainer : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isError
                    ? scheme.onErrorContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null || secondaryActionLabel != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (actionLabel != null)
                    FilledButton.tonal(
                      onPressed: onPressed,
                      child: Text(actionLabel!),
                    ),
                  if (secondaryActionLabel != null)
                    TextButton(
                      onPressed: onSecondaryPressed,
                      child: Text(secondaryActionLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StickyCheckoutBar extends StatelessWidget {
  final Json? chosen;
  final Json? pending;
  final Json? quote;
  final Json? cart;
  final bool quoting;
  final bool busy;
  final String? quoteError;
  final VoidCallback onChooseAddress;
  final VoidCallback onReviewOrder;
  final VoidCallback onResumePending;
  final VoidCallback? onRetryQuote;
  const _StickyCheckoutBar({
    required this.chosen,
    required this.pending,
    required this.quote,
    required this.cart,
    required this.quoting,
    required this.busy,
    required this.quoteError,
    required this.onChooseAddress,
    required this.onReviewOrder,
    required this.onResumePending,
    required this.onRetryQuote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtotalPaise = cart?['merchandiseSubtotalPaise'] as int?;
    final finalPaise = quote?['finalPayablePaise'] as int?;

    String label;
    VoidCallback? onPressed;
    if (pending != null) {
      label = 'Check previous checkout';
      onPressed = busy ? null : onResumePending;
    } else if (chosen == null) {
      label = 'Choose delivery address';
      onPressed = busy ? null : onChooseAddress;
    } else if (quoteError != null) {
      label = 'Change address';
      onPressed = busy ? null : onChooseAddress;
    } else if (quote != null) {
      label = 'Review order';
      onPressed = busy ? null : onReviewOrder;
    } else if (quoting) {
      label = 'Calculating bill…';
      onPressed = null;
    } else {
      label = 'Refresh bill';
      onPressed = busy ? null : onRetryQuote;
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      finalPaise != null
                          ? 'Final payable'
                          : chosen == null
                          ? 'Address needed'
                          : quoteError != null
                          ? 'Address unserviceable'
                          : 'Items subtotal',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                    Text(
                      finalPaise != null
                          ? '₹${formatPaise(finalPaise)}'
                          : subtotalPaise != null
                          ? '₹${formatPaise(subtotalPaise)}'
                          : 'Select address',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: chosen == null && subtotalPaise == null
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                flex: 3,
                fit: FlexFit.loose,
                child: FilledButton(
                  onPressed: onPressed,
                  child: Text(label, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CheckoutScreen extends ConsumerStatefulWidget {
  final Json? quote;
  const CheckoutScreen({super.key, this.quote});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final keyValue = checkoutKey();
  final scrollController = ScrollController();
  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  bool testPayment = false;
  bool busy = false, stale = false;
  String? error;

  Future<void> submit() async {
    if (busy || stale || widget.quote == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    final q = widget.quote!, id = ref.read(customerIdProvider)!;
    final repo = ref.read(commerceRepositoryProvider);
    try {
      final order = await repo.place(id, {
        'cartId': q['cartId'],
        'addressId': q['addressId'],
        'quoteId': q['quoteId'],
        'idempotencyKey': keyValue,
        'paymentMethod': testPayment ? 'RAZORPAY_TEST' : 'DEMO_NO_PAYMENT',
      });
      if (!mounted) return;
      ref.invalidate(cartProvider);
      ref.invalidate(pendingCheckoutProvider);
      if (mounted) context.go('/orders/${order['id']}?placed=true');
    } catch (e) {
      if (e is DioException &&
          [409, 422, 404].contains(e.response?.statusCode)) {
        stale = true;
        await repo.forgetPending(id);
      }
      if (mounted) {
        setState(() => error = commerceError(e));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } finally {
      if (mounted) ref.invalidate(pendingCheckoutProvider);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = widget.quote;

    if (q == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Return to cart for a verified quote before placing an order.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go('/cart'),
                  child: const Text('Return to cart'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final lines = q['lines'] as List;
    final address = Json.from(q['address'] as Map);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          Material(
            color: scheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          q['restaurant']['name'] as String,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  for (final line in lines) ...[
                    Builder(
                      builder: (context) {
                        final rawName = (line['name'] as String?) ?? '';
                        final variant = line['variant'] as Map?;
                        final variantName = variant?['name'] as String?;
                        final cleanName =
                            (variantName != null && variantName.isNotEmpty)
                            ? rawName
                                  .replaceAll(
                                    RegExp(
                                      r'\s*\(\d+\s*pc\)',
                                      caseSensitive: false,
                                    ),
                                    '',
                                  )
                                  .trim()
                            : rawName;
                        final addOns = (line['addOns'] as List?) ?? const [];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${line['quantity']} × $cleanName',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    if (variantName != null &&
                                        variantName.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                scheme.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            variantName,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: scheme.primary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ),
                                    if (addOns.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          [
                                                for (final a in addOns)
                                                  ((a as Map)['name']
                                                          as String?) ??
                                                      '',
                                              ]
                                              .where((s) => s.isNotEmpty)
                                              .join(' · '),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (line['lineTotalPaise'] != null) ...[
                                const SizedBox(width: 10),
                                Text(
                                  '₹${formatPaise(line['lineTotalPaise'] as int)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: scheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Delivery address',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: busy ? null : () => context.go('/cart'),
                        child: const Text('Change address'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${address['recipientName']} · ${address['localityName']}',
                    style: theme.textTheme.labelLarge,
                  ),
                  Text(
                    [
                      address['addressLine1'],
                      if ((address['addressLine2'] as String?)?.isNotEmpty ==
                          true)
                        address['addressLine2'],
                      '${address['localityName']} ${address['postalCode']}',
                    ].join('\n'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OrderBill(q, title: 'Order bill'),
          SwitchListTile(
            title: const Text('Razorpay Test Payment'),
            subtitle: const Text('Test mode only · no real money'),
            value: testPayment,
            onChanged: busy
                ? null
                : (value) => setState(() => testPayment = value),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        testPayment
                            ? 'Test checkout · Payment required'
                            : 'Demo checkout · Unpaid',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        testPayment
                            ? 'Your order is saved first. Open Razorpay TEST on the confirmation screen to pay.'
                            : 'No real payment is collected. Your order records as unpaid and awaits restaurant action.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            _CartNoticeCard(
              icon: Icons.error_outline,
              title: stale ? 'Quote expired or changed' : 'Checkout paused',
              message: error!,
              isError: true,
              actionLabel: stale ? 'Return to cart for fresh quote' : null,
              onPressed: stale ? () => context.go('/cart') : null,
            ),
          ],
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Final payable', style: theme.textTheme.labelSmall),
                      Text(
                        '₹${formatPaise(q['finalPayablePaise'] as int)}',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const ValueKey('place-order'),
                  onPressed: busy || stale ? null : submit,
                  child: Text(busy ? 'Recording order…' : 'Confirm order'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
