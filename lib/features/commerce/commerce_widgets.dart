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
                            : 'This view is for ${role == 'CUSTOMER' ? 'customers' : 'restaurant owners'}.',
                      ),
                      TextButton(
                        onPressed: () => context.push('/login?return=back'),
                        child: const Text('Sign in'),
                      ),
                      TextButton(
                        onPressed: () => context.go('/'),
                        child: const Text('Continue exploring'),
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
  const AddToCartButton({
    super.key,
    required this.selection,
    this.enabled = true,
  });
  @override
  ConsumerState<AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends ConsumerState<AddToCartButton> {
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
      final repo = ref.read(commerceRepositoryProvider);
      final cart = Json.from(await repo.request('GET', 'cart'));
      var replace = false;
      if (cart['restaurantId'] != null &&
          cart['restaurantId'] != selection['restaurantId']) {
        if (!mounted) return;
        replace = await confirmCartSwitch(context);
        if (!replace) return;
      }
      await repo.request('POST', 'cart/items', {
        ...selection,
        'expectedVersion': cart['version'],
        'replaceRestaurant': replace,
      });
      if (!mounted) return;
      ref.invalidate(cartProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Added to your cart'),
            action: SnackBarAction(
              label: 'View cart',
              onPressed: () => context.push('/cart'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      FilledButton.icon(
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
