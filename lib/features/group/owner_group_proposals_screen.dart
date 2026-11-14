import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../commerce/commerce_repository.dart';
import '../commerce/live_orders.dart';
import '../finder/finder_theme.dart';
import 'group_api.dart';
import 'group_screens.dart' show groupError;

final ownerProposalsProvider = FutureProvider.autoDispose.family<List<Json>, String?>((ref, restaurantId) => ref.watch(groupApiProvider).ownerProposals(restaurantId: restaurantId));

/// Restaurant owner: group price requests for the outlets this owner is authorized for.
class OwnerGroupProposalsScreen extends ConsumerStatefulWidget {
  final String? restaurantId;
  const OwnerGroupProposalsScreen({super.key, this.restaurantId});
  @override
  ConsumerState<OwnerGroupProposalsScreen> createState() => _OwnerGroupProposalsScreenState();
}

class _OwnerGroupProposalsScreenState extends ConsumerState<OwnerGroupProposalsScreen> {
  String? busyId;

  void _refresh() => ref.invalidate(ownerProposalsProvider(widget.restaurantId));

  Future<void> _respond(Json p, String action) async {
    int? counter;
    String? note;
    if (action == 'counter') {
      final r = await _counterDialog(p);
      if (r == null) return;
      (counter, note) = r;
    } else if (action == 'reject') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline this request?'),
          content: Text('The group asked for ${rupees(p['proposedTotalPaise'] as int)} instead of ${rupees(p['normalTotalPaise'] as int)}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
            FilledButton(key: const ValueKey('owner-reject-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Decline')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => busyId = p['id'] as String);
    try {
      await ref.read(groupApiProvider).ownerRespond(p['id'] as String, action, counterTotalPaise: counter, note: note);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action == 'accept' ? 'Accepted' : action == 'reject' ? 'Declined' : 'Counteroffer sent')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(groupError(e))));
    } finally {
      _refresh();
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<(int, String?)?> _counterDialog(Json p) async {
    final low = p['proposedTotalPaise'] as int, high = p['normalTotalPaise'] as int;
    final amount = TextEditingController(text: '${((low + high) / 2 / 100).round()}');
    final note = TextEditingController();
    String? error;
    return showDialog<(int, String?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Counteroffer'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Enter the final amount the group would pay, between ${rupees(low + 100)} and ${rupees(high - 100)}.'),
            TextField(
              key: const ValueKey('owner-counter-amount'),
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(prefixText: '₹ ', errorText: error),
            ),
            TextField(controller: note, maxLength: 120, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
            FilledButton(
              key: const ValueKey('owner-counter-send'),
              onPressed: () {
                final v = (int.tryParse(amount.text.trim()) ?? 0) * 100;
                if (v <= low || v >= high) return set(() => error = 'Must be above ${rupees(low)} and below ${rupees(high)}');
                Navigator.pop(context, (v, note.text.trim().isEmpty ? null : note.text.trim()));
              },
              child: const Text('Send counteroffer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveOrdersProvider, (_, next) {
      final u = next.asData?.value;
      if (u != null && (u.groupProposalsChanged || u.reconcile)) _refresh();
    });
    final c = FinderColors.of(context);
    final list = ref.watch(ownerProposalsProvider(widget.restaurantId));
    const tabs = [('Pending', ['PENDING']), ('Countered', ['COUNTERED']), ('Accepted', ['ACCEPTED', 'USED']), ('Closed', ['REJECTED', 'EXPIRED', 'WITHDRAWN', 'DECLINED'])];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Group proposals'),
          actions: [IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh))],
          bottom: TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t.$1)]),
        ),
        body: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(groupError(e), textAlign: TextAlign.center))),
          data: (all) => TabBarView(children: [
            for (final t in tabs)
              RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: Builder(builder: (context) {
                  final rows = all.where((p) => t.$2.contains(p['status'])).toList();
                  if (rows.isEmpty) return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text('Nothing here yet.', textAlign: TextAlign.center, style: TextStyle(color: c.muted)))]);
                  return ListView(padding: const EdgeInsets.all(16), children: [for (final p in rows) _ProposalCard(p: p, busy: busyId == p['id'], onAction: (a) => _respond(p, a))]);
                }),
              ),
          ]),
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final Json p;
  final bool busy;
  final void Function(String action) onAction;
  const _ProposalCard({required this.p, required this.busy, required this.onAction});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget line(String a, String b, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [Expanded(child: Text(a, style: text.bodyMedium?.copyWith(color: color))), Text(b, style: (bold ? text.titleSmall : text.bodyMedium)?.copyWith(color: color, fontWeight: bold ? FontWeight.w800 : null))]),
        );
    final expires = DateTime.tryParse((p['status'] == 'PENDING' ? p['responseExpiresAt'] : p['offerExpiresAt'])?.toString() ?? '')?.toLocal();
    return Card(
      key: ValueKey('proposal-${p['id']}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${p['groupReference']}${p['groupName'] != null ? ' · ${p['groupName']}' : ''}', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            Text(p['status'] as String, style: text.labelMedium?.copyWith(color: c.forest)),
          ]),
          Text('${p['restaurantName']}${p['outletLocality'] != null ? ' · ${(p['outletLocality'] as String).split(',').first}' : ''} · ${p['memberCount']} customers', style: text.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: 8),
          for (final i in (p['items'] as List).cast<Map>())
            Text('${i['quantity']} × ${i['name']}${i['variant'] != null ? ' (${i['variant']})' : ''}${(i['addOns'] as List).isNotEmpty ? ' + ${(i['addOns'] as List).join(', ')}' : ''}', style: text.bodyMedium),
          const Divider(),
          line('Normal total', rupees(p['normalTotalPaise'] as int)),
          line('Group asks for', rupees(p['proposedTotalPaise'] as int), bold: true),
          line('Requested discount', '${rupees(p['requestedReductionPaise'] as int)} (${p['requestedReductionPercent']}%)', color: c.warn),
          if (p['counterTotalPaise'] != null) line('Your counteroffer', rupees(p['counterTotalPaise'] as int)),
          if (p['agreedTotalPaise'] != null) line('Agreed', rupees(p['agreedTotalPaise'] as int), bold: true, color: c.success),
          if (expires != null && ['PENDING', 'COUNTERED', 'ACCEPTED'].contains(p['status'])) Text('Expires ${TimeOfDay.fromDateTime(expires).format(context)}', style: text.bodySmall),
          if (p['orderId'] != null) Text('Order placed — see Kitchen operations', style: text.bodySmall?.copyWith(color: c.success)),
          if (p['status'] == 'PENDING') ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
              OutlinedButton(key: ValueKey('owner-reject-${p['id']}'), onPressed: busy ? null : () => onAction('reject'), child: const Text('Decline')),
              OutlinedButton(key: ValueKey('owner-counter-${p['id']}'), onPressed: busy ? null : () => onAction('counter'), child: const Text('Counteroffer')),
              FilledButton(key: ValueKey('owner-accept-${p['id']}'), style: FilledButton.styleFrom(backgroundColor: c.forest, foregroundColor: c.onForest), onPressed: busy ? null : () => onAction('accept'), child: Text('Accept ${rupees(p['proposedTotalPaise'] as int)}')),
            ]),
          ],
        ]),
      ),
    );
  }
}
