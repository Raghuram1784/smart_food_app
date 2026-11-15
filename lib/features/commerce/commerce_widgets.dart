import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../auth/auth_provider.dart';
import '../catalog/catalog.dart';
import 'commerce_repository.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String shortOrderRef(String orderNumber) {
  final trimmed = orderNumber.trim();
  if (trimmed.length <= 14) return trimmed;
  return '${trimmed.substring(0, 7)}…${trimmed.substring(trimmed.length - 4)}';
}

String formatOrderTime(String isoString) {
  final parsed = DateTime.tryParse(isoString);
  if (parsed == null) return isoString;
  final local = parsed.toLocal();
  final month = _months[local.month - 1];
  final hour24 = local.hour;
  final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour24 >= 12 ? 'PM' : 'AM';
  return '${local.day} $month, $hour12:$minute $period';
}

String orderStatus(String value) => switch (value) {
  'ACCEPTED' => 'Accepted',
  'PREPARING' => 'Preparing',
  'READY_FOR_PICKUP' => 'Ready for pickup',
  'PICKED_UP' => 'Picked up',
  'OUT_FOR_DELIVERY' => 'Out for delivery',
  'DELIVERED' => 'Delivered',
  'REJECTED' => 'Rejected',
  'AWAITING_PAYMENT' => 'Awaiting test payment',
  'PENDING_RESTAURANT' => 'Awaiting restaurant action',
  _ => value.toLowerCase().replaceAll('_', ' '),
};

String paymentStatusLabel(String value, {bool concise = false}) {
  if (value == 'UNPAID') {
    return concise ? 'Unpaid · demo' : 'No real payment collected';
  }
  if (value == 'PAID') return 'Test payment confirmed';
  return value.toLowerCase().replaceAll('_', ' ');
}

String _roleDescription(String role) {
  switch (role) {
    case 'RESTAURANT_OWNER':
      return 'restaurant owners';
    case 'DELIVERY_PARTNER':
      return 'delivery partners';
    case 'ADMIN':
      return 'administrators';
    case 'CUSTOMER':
    default:
      return 'customers';
  }
}

class CommerceGate extends ConsumerWidget {
  final Widget child;
  final String role;
  const CommerceGate({super.key, required this.child, this.role = 'CUSTOMER'});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(authProvider)
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Your account')),
          body: CommerceFailure(e, () => ref.invalidate(authProvider)),
        ),
        data: (s) => s != null && s.user.roles.contains(role)
            ? KeyedSubtree(key: ValueKey(s.user.id), child: child)
            : Scaffold(
                appBar: AppBar(title: const Text('Your account')),
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s == null
                            ? 'Sign in to continue.'
                            : 'This view requires authorization for ${_roleDescription(role)}.',
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.push('/login?return=back'),
                        child: const Text('Sign in with a different account'),
                      ),
                      TextButton(
                        onPressed: () => context.go('/'),
                        child: const Text('Return to discovery'),
                      ),
                    ],
                  ),
                ),
              ),
      );
}

class CommerceFailure extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const CommerceFailure(this.error, this.retry, {super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(commerceError(error), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class OrderStatusBadge extends StatelessWidget {
  final String status;
  const OrderStatusBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final culinary = theme.extension<CulinaryColors>();
    final bg = culinary?.peach ?? scheme.secondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        orderStatus(status),
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class PaymentTag extends StatelessWidget {
  final String paymentStatus;
  final bool concise;
  const PaymentTag(this.paymentStatus, {super.key, this.concise = false});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        paymentStatusLabel(paymentStatus, concise: concise),
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class CopyOrderRefButton extends StatelessWidget {
  final String orderNumber;
  const CopyOrderRefButton(this.orderNumber, {super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    visualDensity: VisualDensity.compact,
    tooltip: 'Copy full order reference',
    onPressed: () async {
      await Clipboard.setData(ClipboardData(text: orderNumber));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full order reference copied')),
      );
    },
    icon: const Icon(Icons.copy_rounded, size: 18),
  );
}

class OrderBill extends StatelessWidget {
  final Json data;
  final String? title;
  final VoidCallback? onRefresh;
  const OrderBill(this.data, {super.key, this.title, this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final basePaise = (data['basePaise'] ?? data['itemSubtotalPaise']) as int;
    final customizationsPaise =
        (data['customizationTotalPaise'] ??
                ((data['variantPaise'] ?? 0) + (data['addOnPaise'] ?? 0)))
            as int;
    final packagingPaise = (data['packagingPaise'] ?? 0) as int;
    final deliveryPaise = (data['deliveryPaise'] ?? 0) as int;
    final platformPaise = (data['platformPaise'] ?? 0) as int;
    final discountPaise = (data['discountPaise'] ?? 0) as int;
    final taxPaise = (data['taxPaise'] ?? 0) as int;

    final rows = <(String, int)>[
      ('Items', basePaise),
      if (customizationsPaise > 0) ('Customizations', customizationsPaise),
      ('Packaging', packagingPaise),
      ('Delivery', deliveryPaise),
      ('Platform fee', platformPaise),
      if (discountPaise > 0) ('Discount', -discountPaise),
      if (taxPaise > 0) ('Tax', taxPaise),
    ];

    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || onRefresh != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title ?? 'Bill summary',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (onRefresh != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh bill'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            for (final (label, amount) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodyMedium),
                    ),
                    Text(
                      '${amount < 0 ? '−' : ''}₹${formatPaise(amount.abs())}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Final payable', style: theme.textTheme.titleMedium),
                      Text(
                        'All applicable fees included',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${formatPaise(data['finalPayablePaise'])}',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmCartSwitch(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Start a new cart?'),
    content: const Text(
      'Your cart contains items from another restaurant. Replace your cart to continue?',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Keep existing cart'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Clear and switch restaurant'),
      ),
    ],
  ),
).then((v) => v ?? false);

class AddToCartButton extends ConsumerStatefulWidget {
  final Json selection;
  final bool enabled;

  /// Dish name for the confirmation toast.
  final String? itemName;

  /// Optional check run after sign-in and before the cart is touched (e.g. an
  /// over-budget or price-change confirmation). Returning false cancels.
  final Future<bool> Function()? beforeAdd;

  /// Inline button for cards (no top spacing, not stretched).
  final bool compact;

  /// Start the add flow once when first shown ("add the first option" in the finder).
  final bool autoStart;
  const AddToCartButton({
    super.key,
    required this.selection,
    this.enabled = true,
    this.itemName,
    this.beforeAdd,
    this.compact = false,
    this.autoStart = false,
  });
  @override
  ConsumerState<AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends ConsumerState<AddToCartButton> {
  @override
  void initState() {
    super.initState();
    if (widget.autoStart) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) add(); });
  }

  bool busy = false;
  String? error;
  Future<void> add() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final selection = Json.from(widget.selection);
    try {
      var session = await ref.read(authProvider.future);
      if (!mounted) return;
      if (session == null) {
        if (!mounted) return;
        await context.push('/login?return=back');
        if (!mounted) return;
        session = ref.read(authProvider).asData?.value;
      }
      if (session == null) return;
      if (!session.user.roles.contains('CUSTOMER')) {
        setState(() => error = 'Sign in with a customer account to add meals.');
        return;
      }
      if (widget.beforeAdd != null && !await widget.beforeAdd!()) return;
      if (!mounted) return;
      final repo = ref.read(commerceRepositoryProvider);
      final cart = Json.from(await repo.request('GET', 'cart'));
      var replace = false;
      if (cart['restaurantId'] != null &&
          cart['restaurantId'] != selection['restaurantId']) {
        if (!mounted) return;
        replace = await confirmCartSwitch(context);
        if (!replace) return;
      }
      final updated = await repo.request('POST', 'cart/items', {
        ...selection,
        'expectedVersion': cart['version'],
        'replaceRestaurant': replace,
      });
      if (!mounted) return;
      ref.invalidate(cartProvider);
      // Only after the server confirmed the mutation: top toast in the ROOT
      // overlay (a bottom SnackBar was hidden behind the dish sheet).
      final count =
          (updated is Map ? updated['items'] as List? : null)?.fold<int>(
            0,
            (n, i) => n + ((i as Map)['quantity'] as int? ?? 0),
          ) ??
          0;
      showCartAddedToast(
        context,
        name: widget.itemName ?? 'Item',
        quantity: (selection['quantity'] as int?) ?? 1,
        cartCount: count,
      );
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: widget.compact ? CrossAxisAlignment.end : CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!widget.compact) const SizedBox(height: 16),
      FilledButton.icon(
        style: widget.compact ? FilledButton.styleFrom(minimumSize: const Size(48, 44), padding: const EdgeInsets.symmetric(horizontal: 16)) : null,
        key: const ValueKey('add-to-cart'),
        onPressed: busy || !widget.enabled ? null : add,
        icon: const Icon(Icons.shopping_bag_outlined),
        label: Text(busy ? 'Adding…' : 'Add to cart'),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

class CartShortcut extends ConsumerWidget {
  const CartShortcut({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(customerIdProvider) == null) return const SizedBox.shrink();
    final cart = ref.watch(cartProvider).asData?.value;
    final count = (cart?['items'] as List? ?? []).fold<int>(
      0,
      (n, i) => n + (i['quantity'] as int),
    );
    return IconButton(
      tooltip: 'Your cart',
      onPressed: () => context.push('/cart'),
      icon: Badge(
        label: Text('$count'),
        isLabelVisible: count > 0,
        child: const Icon(Icons.shopping_bag_outlined),
      ),
    );
  }
}

OverlayEntry? _cartToast;

/// Top-of-screen "added to cart" confirmation with a View cart action.
/// One at a time; auto-dismisses; inserted into the root overlay so it is
/// visible above bottom sheets and every route.
void showCartAddedToast(
  BuildContext context, {
  required String name,
  required int quantity,
  required int cartCount,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final router = GoRouter.maybeOf(context);
  final rootNavigator = Navigator.maybeOf(context, rootNavigator: true);
  void close() {
    final entry = _cartToast;
    _cartToast = null;
    if (entry == null) return;
    // The overlay may already be gone (route/app disposed): only remove if mounted.
    if (entry.mounted) {
      entry.remove();
      entry.dispose();
    }
  }

  close();
  _cartToast = OverlayEntry(
    // The auto-dismiss timer lives in a widget so it dies with the entry/tree.
    builder: (ctx) => _AutoDismiss(
      after: const Duration(seconds: 4),
      onDismiss: close,
      child: Builder(
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final scheme = theme.colorScheme;
          return Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  key: const ValueKey('cart-added-toast'),
                  elevation: 8,
                  color: scheme.inverseSurface,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: scheme.inversePrimary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Added $quantity × $name',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: scheme.onInverseSurface,
                                ),
                              ),
                              if (cartCount > 0)
                                Text(
                                  '$cartCount ${cartCount == 1 ? 'item' : 'items'} in your cart',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onInverseSurface.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            close();
                            // Close the dish sheet if open, then open the cart.
                            rootNavigator?.popUntil((r) => r is! PopupRoute);
                            router?.push('/cart');
                          },
                          child: Text(
                            'View cart',
                            style: TextStyle(
                              color: scheme.inversePrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  overlay.insert(_cartToast!);
}

class _AutoDismiss extends StatefulWidget {
  final Duration after;
  final VoidCallback onDismiss;
  final Widget child;
  const _AutoDismiss({
    required this.after,
    required this.onDismiss,
    required this.child,
  });
  @override
  State<_AutoDismiss> createState() => _AutoDismissState();
}

class _AutoDismissState extends State<_AutoDismiss> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.after, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Sticky "View cart" bar shown while the server cart has items.
class ViewCartBar extends ConsumerWidget {
  const ViewCartBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(customerIdProvider) == null) return const SizedBox.shrink();
    final cart = ref.watch(cartProvider).asData?.value;
    final items = (cart?['items'] as List?) ?? const [];
    final count = items.fold<int>(
      0,
      (n, i) => n + ((i as Map)['quantity'] as int? ?? 0),
    );
    if (count == 0) return const SizedBox.shrink();
    final subtotal = cart?['merchandiseSubtotalPaise'];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Material(
          key: const ValueKey('view-cart-bar'),
          color: scheme.primary,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/cart'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.shopping_bag, color: scheme.onPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$count ${count == 1 ? 'item' : 'items'}${subtotal is int ? ' · ₹${formatPaise(subtotal)}' : ''}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'View cart',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onPrimary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
