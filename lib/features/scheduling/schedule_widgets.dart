import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../commerce/commerce_repository.dart';

String scheduleTime(dynamic raw, {bool date = false}) {
  final utc = DateTime.tryParse('$raw');
  if (utc == null) return '—';
  final d = utc.toUtc().add(const Duration(minutes: 330));
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final time =
      '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  return date ? '${d.day}/${d.month} · $time IST' : time;
}

String scheduleWindow(Map o) =>
    '${scheduleTime(o['deliveryWindowStart'])} – ${scheduleTime(o['deliveryWindowEnd'])} IST';

/// null means Schedule for Later is selected but no server slot has been chosen.
class SchedulePicker extends ConsumerStatefulWidget {
  final String restaurantId;
  final ValueChanged<Json?> onChanged;
  final bool enabled;
  const SchedulePicker({
    super.key,
    required this.restaurantId,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  ConsumerState<SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends ConsumerState<SchedulePicker> {
  bool later = false, loading = false;
  Json? data, selected;
  String? date, error;
  int generation = 0;
  Future<void> load([String? day]) async {
    final run = ++generation;
    setState(() {
      loading = true;
      error = null;
      selected = null;
      date = day;
    });
    widget.onChanged(null);
    try {
      final r = Json.from(
        await ref
            .read(commerceRepositoryProvider)
            .request(
              'GET',
              'restaurants/${widget.restaurantId}/delivery-slots${day == null ? '' : '?date=$day'}',
            ),
      );
      if (mounted && run == generation) {
        setState(() {
          data = r;
          date = r['date'] as String;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && run == generation) {
        setState(() {
          error = commerceError(e);
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dates = (data?['dates'] as List?) ?? [];
    final slots = (data?['slots'] as List?) ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'When should we deliver?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Deliver Now'),
                  selected: !later,
                  onSelected: !widget.enabled
                      ? null
                      : (_) {
                          generation++;
                          setState(() {
                            later = false;
                            loading = false;
                          });
                          widget.onChanged({});
                        },
                ),
                ChoiceChip(
                  key: const ValueKey('schedule-later'),
                  label: const Text('Schedule for Later'),
                  selected: later,
                  onSelected: !widget.enabled
                      ? null
                      : (_) {
                          setState(() => later = true);
                          load();
                        },
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: !later
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        if (dates.isNotEmpty)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final day in dates)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(
                                        '${day.toString().substring(8)}/${day.toString().substring(5, 7)}',
                                      ),
                                      selected: day == date,
                                      onSelected: !widget.enabled || loading
                                          ? null
                                          : (_) => load(day as String),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (loading)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: LinearProgressIndicator(),
                          )
                        else if (error != null)
                          Column(
                            children: [
                              Text(
                                error!,
                                style: TextStyle(color: scheme.error),
                              ),
                              TextButton(
                                onPressed: () => load(date),
                                child: const Text('Retry slots'),
                              ),
                            ],
                          )
                        else if (slots.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No available slots on this date. Choose another day.',
                            ),
                          )
                        else
                          SizedBox(
                            height: 62,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: slots.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final slot = Json.from(slots[index] as Map);
                                return ChoiceChip(
                                  key: ValueKey('slot-$index'),
                                  label: Text(
                                    scheduleTime(slot['scheduledDeliveryAt']),
                                  ),
                                  selected:
                                      selected?['scheduledDeliveryAt'] ==
                                      slot['scheduledDeliveryAt'],
                                  onSelected: !widget.enabled
                                      ? null
                                      : (_) {
                                          setState(() => selected = slot);
                                          widget.onChanged({
                                            'deliveryMode': 'SCHEDULED',
                                            'scheduledDeliveryAt':
                                                slot['scheduledDeliveryAt'],
                                          });
                                        },
                                );
                              },
                            ),
                          ),
                        if (selected != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Target delivery window',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                Text(
                                  scheduleWindow(selected!),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'A ten-minute target window, not a guarantee. We’ll update you if your order is running late.',
                        ),
                        if (data?['demoFast'] == true)
                          const Text(
                            'Development demo · shortened preparation and travel estimates',
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScheduleCard extends StatefulWidget {
  final Json order;
  final bool compact;
  const ScheduleCard({super.key, required this.order, this.compact = false});
  @override
  State<ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<ScheduleCard> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    if (o['deliveryMode'] != 'SCHEDULED') return const SizedBox.shrink();
    const labels = {
      'SCHEDULED': 'Scheduled',
      'ON_TRACK': 'On track',
      'PREPARING': 'Preparing',
      'AT_RISK': 'At risk of delay',
      'DELAYED': 'Delayed',
      'DELIVERED_WITHIN_WINDOW': 'Delivered within window',
      'DELIVERED_OUTSIDE_WINDOW': 'Delivered outside window',
      'CANCELED': 'Canceled',
      'REJECTED': 'Rejected',
    };
    final label = labels[o['scheduleIndicator']] ?? 'Scheduled';
    final due = DateTime.tryParse('${o['scheduledDeliveryAt']}');
    final left = due?.difference(DateTime.now()).inMinutes;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          Text(scheduleTime(o['scheduledDeliveryAt'], date: true)),
          Text(scheduleWindow(o)),
          if (!widget.compact) ...[
            Text(
              'Preparation start: ${scheduleTime(o['preparationStartAt'])} IST',
            ),
            Text('Expected pickup: ${scheduleTime(o['expectedPickupAt'])} IST'),
            if (o['actualDeliveryAt'] != null)
              Text(
                'Delivered: ${scheduleTime(o['actualDeliveryAt'], date: true)}',
              )
            else if (!['CANCELED', 'REJECTED'].contains(o['status']))
              Text(
                left != null && left > 0
                    ? 'Target in $left minutes'
                    : 'Target time reached · refresh for progress',
              ),
            const Text('Estimated from kitchen progress; no live GPS.'),
          ],
        ],
      ),
    );
  }
}

class ScheduledCancelButton extends ConsumerWidget {
  final Json order;
  const ScheduledCancelButton({super.key, required this.order});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = DateTime.tryParse('${order['preparationStartAt']}');
    if (order['deliveryMode'] != 'SCHEDULED' ||
        ![
          'AWAITING_PAYMENT',
          'PENDING_RESTAURANT',
          'ACCEPTED',
        ].contains(order['status']) ||
        due == null ||
        !due.isAfter(DateTime.now())) {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Cancel scheduled order?'),
            content: const Text(
              'Your slot will be released. Any captured payment requires refund review; this does not confirm a refund.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep order'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Cancel order'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await ref.read(commerceRepositoryProvider).request(
            'POST',
            'orders/${order['id']}/cancel-scheduled',
            {'expectedVersion': order['version']},
          );
          ref.invalidate(commerceReadProvider);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(commerceError(e))));
          }
        }
      },
      child: const Text('Cancel scheduled order'),
    );
  }
}
