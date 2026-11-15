import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog.dart';
import '../commerce/commerce_repository.dart';
import '../discovery/home_screen.dart' show DishCard;
import '../finder/finder_theme.dart';
import '../location/delivery_destination.dart';

String _inr(num paise) {
  final neg = paise < 0;
  final v = (paise.abs() / 100);
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  final parts = s.split('.');
  var whole = parts[0];
  if (whole.length > 3) {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    whole = '${groups.join(',')},$last3';
  }
  return '${neg ? '−' : ''}₹$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String _when(Object? iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${m[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String _status(String s) => s.split('_').map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(' ');

// ------------------------------------------------------------------ shared pieces

class _Kpi extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final String? hint;
  final Color? accent;
  const _Kpi(this.icon, this.label, this.value, {this.hint, this.accent});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final a = accent ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: a.withValues(alpha: .14), shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: a),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant))),
        ]),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: text.titleLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700)),
        ),
        if (hint != null) Text(hint!, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<Widget> children;
  const _Grid(this.children);
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final x in children) SizedBox(width: w, child: x)]);
      });
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Section(this.title, this.icon, this.child);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

class _Panel extends StatelessWidget {
  final List<Widget> children;
  const _Panel(this.children);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant)),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
          children[i],
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String title, subtitle, amount;
  final Color? amountColor;
  final IconData? icon;
  const _Row(this.title, this.subtitle, this.amount, {this.amountColor, this.icon});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListTile(
      dense: true,
      leading: icon == null ? null : Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge?.copyWith(color: scheme.onSurface)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      trailing: Text(amount, style: text.labelLarge?.copyWith(color: amountColor ?? scheme.onSurface, fontWeight: FontWeight.w700)),
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty(this.message);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _Bars extends StatelessWidget {
  final List<Json> series;
  const _Bars(this.series);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final max = series.fold<int>(0, (m, s) => (s['revenuePaise'] as int) > m ? s['revenuePaise'] as int : m);
    final total = series.fold<int>(0, (m, s) => m + (s['revenuePaise'] as int));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Revenue, last ${series.length} days · ${_inr(total)}', style: text.labelLarge?.copyWith(color: scheme.onSurface)),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final s in series)
              Expanded(
                child: Tooltip(
                  message: '${s['date']}: ${_inr(s['revenuePaise'] as int)} · ${s['orders']} orders',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Container(
                      height: max == 0 ? 2 : 4 + 112 * (s['revenuePaise'] as int) / max,
                      decoration: BoxDecoration(
                        color: (s['revenuePaise'] as int) > 0 ? scheme.primary : scheme.outlineVariant,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('${series.first['date']}'.substring(5), style: text.labelSmall),
          const Spacer(),
          Text('${series.last['date']}'.substring(5), style: text.labelSmall),
        ]),
      ]),
    );
  }
}

class _RangePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _RangePicker(this.value, this.onChanged);
  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'day', label: Text('Today')),
          ButtonSegment(value: 'week', label: Text('Week')),
          ButtonSegment(value: 'month', label: Text('Month')),
          ButtonSegment(value: 'all', label: Text('All')),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

Widget _loadError(BuildContext context, Object e, VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(commerceError(e), textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: retry, child: const Text('Try again')),
        ]),
      ),
    );

// ------------------------------------------------------------------ admin

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  String range = 'week';
  @override
  Widget build(BuildContext context) {
    final path = 'admin/dashboard?range=$range';
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin overview'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(commerceReadProvider(path));
              ref.invalidate(commerceReadProvider('admin/rider-payouts'));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(commerceReadProvider('admin/rider-payouts'));
          ref.invalidate(commerceReadProvider(path));
          await ref.read(commerceReadProvider(path).future);
        },
        child: ref.watch(commerceReadProvider(path)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _loadError(context, e, () => ref.invalidate(commerceReadProvider(path))),
              data: (raw) {
                final d = Json.from(raw as Map);
                final people = Json.from(d['people'] as Map), orders = Json.from(d['orders'] as Map), f = Json.from(d['finance'] as Map);
                final series = (d['series'] as List).cast<Map>().map(Json.from).toList();
                final restaurants = (d['restaurants'] as List).cast<Map>().map(Json.from).toList();
                final recent = (d['recentOrders'] as List).cast<Map>().map(Json.from).toList();
                final tx = (d['transactions'] as List).cast<Map>().map(Json.from).toList();
                return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                  SingleChildScrollView(scrollDirection: Axis.horizontal, child: _RangePicker(range, (v) => setState(() => range = v))),
                  _Section('Platform', Icons.hub_outlined, _Grid([
                    _Kpi(Icons.people_alt_outlined, 'Customers', '${people['customers']}'),
                    _Kpi(Icons.storefront_outlined, 'Restaurants', '${people['restaurants']}'),
                    _Kpi(Icons.two_wheeler_outlined, 'Delivery partners', '${people['deliveryPartners']}'),
                  ])),
                  _Section('Orders', Icons.receipt_long_outlined, _Grid([
                    _Kpi(Icons.receipt_long_outlined, 'Total orders', '${orders['total']}', hint: orders['awaitingPayment'] == 0 ? null : '${orders['awaitingPayment']} awaiting payment'),
                    _Kpi(Icons.local_fire_department_outlined, 'Active', '${orders['active']}', accent: scheme.tertiary),
                    _Kpi(Icons.check_circle_outline, 'Completed', '${orders['completed']}', accent: Colors.green.shade600),
                    _Kpi(Icons.cancel_outlined, 'Cancelled / rejected', '${orders['cancelled']}', accent: scheme.error),
                  ])),
                  _Section('Finance', Icons.account_balance_wallet_outlined, _Grid([
                    _Kpi(Icons.currency_rupee, 'Order revenue', _inr(f['orderRevenuePaise'] as int), hint: '${_inr(f['paidOnlinePaise'] as int)} paid online (test mode)'),
                    _Kpi(Icons.savings_outlined, 'Platform earnings', _inr(f['platformEarningsPaise'] as int), hint: 'Fees ${_inr(f['platformFeesPaise'] as int)} + rider commission ${_inr(f['riderCommissionPaise'] as int)}'),
                    _Kpi(Icons.delivery_dining_outlined, 'Rider earnings (net)', _inr(f['riderNetPaise'] as int), hint: 'Gross ${_inr(f['riderGrossPaise'] as int)} · ${d['commissionPercent']}% commission'),
                    _Kpi(Icons.payments_outlined, 'Rider payouts', _inr(f['payoutsPendingPaise'] as int), hint: 'pending · ${_inr(f['payoutsCompletedPaise'] as int)} paid in period'),
                  ])),
                  _Section('Revenue trend', Icons.bar_chart_rounded, _Bars(series)),
                  _Section('Restaurant performance', Icons.leaderboard_outlined, restaurants.isEmpty
                      ? const _Panel([_Empty('No orders in this period.')])
                      : _Panel([
                          for (final r in restaurants)
                            _Row(r['name'] as String, '${r['orders']} orders · ${r['completed']} completed', _inr(r['revenuePaise'] as int), icon: Icons.storefront_outlined),
                        ])),
                  const _Section('Rider payouts', Icons.account_balance_outlined, _RiderPayouts()),
                  _Section('Recent orders', Icons.history, recent.isEmpty
                      ? const _Panel([_Empty('No orders in this period.')])
                      : _Panel([
                          for (final o in recent)
                            _Row('${o['orderNumber']}', '${o['restaurantName']} · ${_status(o['status'] as String)} · ${_when(o['createdAt'])}', _inr(o['finalPayablePaise'] as int)),
                        ])),
                  _Section('Recent transactions', Icons.swap_vert_rounded, tx.isEmpty
                      ? const _Panel([_Empty('No captured payments or payouts yet.')])
                      : _Panel([
                          for (final t in tx)
                            _Row(t['label'] as String, '${t['note']} · ${_when(t['at'])}', _inr(t['amountPaise'] as int),
                                icon: t['type'] == 'PAYOUT' ? Icons.north_east_rounded : Icons.south_west_rounded,
                                amountColor: (t['amountPaise'] as int) < 0 ? scheme.error : Colors.green.shade600),
                        ])),
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text('${d['definitions']}', style: Theme.of(context).textTheme.bodySmall),
                  ),
                ]);
              },
            ),
      ),
    );
  }
}

class _RiderPayouts extends ConsumerWidget {
  const _RiderPayouts();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const path = 'admin/rider-payouts';
    return ref.watch(commerceReadProvider(path)).when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => _Panel([_Empty(commerceError(e))]),
          data: (raw) {
            final riders = (raw as List).cast<Map>().map(Json.from).toList();
            if (riders.isEmpty) return const _Panel([_Empty('No delivery partners yet.')]);
            final scheme = Theme.of(context).colorScheme;
            final text = Theme.of(context).textTheme;
            return _Panel([
              for (final r in riders)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['name'] as String, style: text.labelLarge?.copyWith(color: scheme.onSurface)),
                        Text('${r['deliveries']} deliveries · net ${_inr(r['netPaise'] as int)} · paid ${_inr(r['completedPayoutPaise'] as int)}', style: text.bodySmall),
                        Text('Pending ${_inr(r['pendingPayoutPaise'] as int)}', style: text.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    FilledButton.tonal(
                      onPressed: (r['pendingPayoutPaise'] as int) < 100 ? null : () => _recordPayout(context, ref, r),
                      child: const Text('Record payout'),
                    ),
                  ]),
                ),
            ]);
          },
        );
  }

  Future<void> _recordPayout(BuildContext context, WidgetRef ref, Json r) async {
    final pending = r['pendingPayoutPaise'] as int;
    final amount = TextEditingController(text: (pending / 100).toStringAsFixed(2));
    final reference = TextEditingController();
    final key = checkoutKey();
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text('Payout to ${r['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pending balance ${_inr(pending)}. This records a manual settlement only; no money is transferred by the app.', style: Theme.of(dialogContext).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (₹)')),
            const SizedBox(height: 10),
            TextField(controller: reference, maxLength: 80, decoration: const InputDecoration(labelText: 'Reference (optional)', hintText: 'e.g. UPI ref / cash')),
            if (error != null) Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
          ]),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final paise = ((double.tryParse(amount.text.trim()) ?? 0) * 100).round();
                      if (paise < 100 || paise > pending) {
                        setState(() => error = 'Enter an amount between ₹1 and ${_inr(pending)}.');
                        return;
                      }
                      setState(() => busy = true);
                      try {
                        await ref.read(commerceRepositoryProvider).request('POST', 'admin/rider-payouts', {
                          'riderId': r['riderId'],
                          'amountPaise': paise,
                          'idempotencyKey': key,
                          if (reference.text.trim().isNotEmpty) 'reference': reference.text.trim(),
                        });
                        ref.invalidate(commerceReadProvider('admin/rider-payouts'));
                        for (final x in ['day', 'week', 'month', 'all']) {
                          ref.invalidate(commerceReadProvider('admin/dashboard?range=$x'));
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        setState(() {
                          busy = false;
                          error = commerceError(e);
                        });
                      }
                    },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ rider

class RiderEarningsScreen extends ConsumerWidget {
  const RiderEarningsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const path = 'rider/earnings';
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings'), actions: [
        IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(commerceReadProvider(path))),
      ]),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(commerceReadProvider(path).future),
        child: ref.watch(commerceReadProvider(path)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _loadError(context, e, () => ref.invalidate(commerceReadProvider(path))),
              data: (raw) {
                final d = Json.from(raw as Map);
                Json t(String k) => Json.from(d[k] as Map);
                final today = t('today'), week = t('week'), month = t('month'), life = t('lifetime'), pay = t('payouts');
                final history = (d['history'] as List).cast<Map>().map(Json.from).toList();
                final payouts = (pay['history'] as List).cast<Map>().map(Json.from).toList();
                return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("Today's net earnings", style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
                      const SizedBox(height: 6),
                      Text(_inr(today['netPaise'] as int), style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800)),
                      Text('${today['deliveries']} deliveries today · gross ${_inr(today['grossPaise'] as int)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
                    ]),
                  ),
                  _Section('Summary', Icons.insights_outlined, _Grid([
                    _Kpi(Icons.date_range_outlined, 'This week (net)', _inr(week['netPaise'] as int), hint: '${week['deliveries']} deliveries'),
                    _Kpi(Icons.calendar_month_outlined, 'This month (net)', _inr(month['netPaise'] as int), hint: '${month['deliveries']} deliveries'),
                    _Kpi(Icons.task_alt_outlined, 'Completed deliveries', '${life['deliveries']}', accent: Colors.green.shade600),
                    _Kpi(Icons.currency_rupee, 'Gross earnings', _inr(life['grossPaise'] as int)),
                    _Kpi(Icons.percent, 'Platform commission (${d['commissionPercent']}%)', _inr(life['commissionPaise'] as int), accent: scheme.error),
                    _Kpi(Icons.account_balance_wallet_outlined, 'Net payable', _inr(life['netPaise'] as int), accent: Colors.green.shade600),
                    _Kpi(Icons.hourglass_bottom_rounded, 'Pending payout', _inr(pay['pendingPaise'] as int), accent: scheme.tertiary),
                    _Kpi(Icons.verified_outlined, 'Paid out', _inr(pay['completedPaise'] as int)),
                  ])),
                  _Section('Delivery earnings', Icons.receipt_outlined, history.isEmpty
                      ? const _Panel([_Empty('Completed deliveries will appear here.')])
                      : _Panel([
                          for (final h in history)
                            _Row('${h['orderNumber']}', '${h['restaurantName']} · ${_when(h['deliveredAt'])} · gross ${_inr(h['grossPaise'] as int)} − ${_inr(h['commissionPaise'] as int)}', _inr(h['netPaise'] as int), icon: Icons.delivery_dining_outlined),
                        ])),
                  _Section('Payouts', Icons.account_balance_outlined, payouts.isEmpty
                      ? const _Panel([_Empty('No payouts recorded yet.')])
                      : _Panel([
                          for (final p in payouts)
                            _Row('Payout', '${p['reference'] ?? 'Manual settlement'} · ${_when(p['createdAt'])}', _inr(p['amountPaise'] as int), icon: Icons.check_circle_outline, amountColor: Colors.green.shade600),
                        ])),
                  Padding(padding: const EdgeInsets.only(top: 16), child: Text('${d['note']}', style: Theme.of(context).textTheme.bodySmall)),
                ]);
              },
            ),
      ),
    );
  }
}

// ------------------------------------------------------------------ kids meals

class KidsMealsEntry extends StatelessWidget {
  const KidsMealsEntry({super.key});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Kids Meals. Smaller portions, mild flavours.',
      excludeSemantics: true,
      child: Material(
        color: c.onForest.withValues(alpha: .1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.onForest.withValues(alpha: .18))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('kids-entry'),
          onTap: () => context.push('/kids-meals'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Row(children: [
              Container(width: 32, height: 32, decoration: BoxDecoration(color: c.coral, shape: BoxShape.circle), child: Icon(Icons.child_care_rounded, size: 18, color: c.onForest)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Kids Meals', style: text.titleSmall?.copyWith(color: c.onForest, fontWeight: FontWeight.w800)),
                  Text('Smaller portions, mild flavours.', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: c.onForest.withValues(alpha: .8))),
                ]),
              ),
              Icon(Icons.chevron_right, color: c.onForest),
            ]),
          ),
        ),
      ),
    );
  }
}

class KidsMealsScreen extends ConsumerWidget {
  const KidsMealsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ref.watch(deliveryServiceAreaProvider);
    final path = 'kids-meals${area == null ? '' : '?area=${area.id}'}';
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Kids Meals')),
      body: ref.watch(commerceReadProvider(path)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _loadError(context, e, () => ref.invalidate(commerceReadProvider(path))),
            data: (raw) {
              final items = ((raw as Map)['items'] as List).cast<Map<String, dynamic>>();
              final dishes = <Dish>[];
              for (final j in items) {
                try {
                  dishes.add(Dish.fromJson(j));
                } catch (_) {}
              }
              return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    Icon(Icons.child_care_rounded, color: scheme.onPrimaryContainer, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Dishes that restaurants marked as suitable for children${area == null ? '' : ' delivering to ${area.name}'}. Prices are the restaurant menu price; nutrition is shown only where the restaurant provided an estimate.',
                        style: text.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                if (dishes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No Kids Meals are available here yet. Restaurants can mark suitable dishes from their kitchen dashboard.', textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  )
                else
                  LayoutBuilder(builder: (context, c) {
                    final cols = (c.maxWidth / 176).floor().clamp(2, 5);
                    return Wrap(
                      spacing: 10,
                      runSpacing: 12,
                      children: [for (final d in dishes) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: FittedBox(fit: BoxFit.fitWidth, alignment: Alignment.topLeft, child: DishCard(d)))],
                    );
                  }),
              ]);
            },
          ),
    );
  }
}

class OwnerKidsMealsScreen extends ConsumerStatefulWidget {
  final String restaurantId;
  final String? restaurantName;
  const OwnerKidsMealsScreen({super.key, required this.restaurantId, this.restaurantName});
  @override
  ConsumerState<OwnerKidsMealsScreen> createState() => _OwnerKidsMealsScreenState();
}

class _OwnerKidsMealsScreenState extends ConsumerState<OwnerKidsMealsScreen> {
  final overrides = <String, bool>{};
  final busy = <String>{};
  @override
  Widget build(BuildContext context) {
    final path = 'restaurants/${widget.restaurantId}/menu';
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.restaurantName == null ? 'Kids Meals' : 'Kids Meals · ${widget.restaurantName}')),
      body: ref.watch(commerceReadProvider(path)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _loadError(context, e, () => ref.invalidate(commerceReadProvider(path))),
            data: (raw) {
              final sections = ((raw as Map)['sections'] as List).cast<Map>();
              return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text('Switch on dishes that suit children (smaller portion, mild). They appear on the customer Kids Meals page and use the normal cart and checkout.', style: text.bodySmall),
                ),
                for (final s in sections) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 4), child: Text('${s['name']}', style: text.titleSmall?.copyWith(color: scheme.primary))),
                  for (final i in (s['items'] as List).cast<Map>())
                    SwitchListTile(
                      key: ValueKey('kids-${i['id']}'),
                      title: Text('${i['name']}', style: text.labelLarge?.copyWith(color: scheme.onSurface)),
                      subtitle: Text('₹${(i['basePricePaise'] as int) ~/ 100}${(i['nutrition'] as Map?)?['caloriesKcal'] != null ? ' · ~${(i['nutrition'] as Map)['caloriesKcal']} kcal (estimate)' : ''}', style: text.bodySmall),
                      value: overrides[i['id']] ?? (i['isKidsMeal'] as bool? ?? false),
                      onChanged: busy.contains(i['id'])
                          ? null
                          : (v) async {
                              final id = i['id'] as String;
                              setState(() {
                                busy.add(id);
                                overrides[id] = v;
                              });
                              try {
                                await ref.read(commerceRepositoryProvider).request('PATCH', 'owner/menu-items/$id/kids-meal', {'isKidsMeal': v});
                              } catch (e) {
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(commerceError(e))));
                                setState(() => overrides[id] = !v);
                              } finally {
                                if (mounted) setState(() => busy.remove(id));
                              }
                            },
                    ),
                ],
              ]);
            },
          ),
    );
  }
}
