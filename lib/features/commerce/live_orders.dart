import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';
import 'commerce_repository.dart';

class LiveOrderUpdate {
  final String connection;
  final String? orderId;
  final bool reconcile;

  /// Server event type (e.g. RIDER_ASSIGNED, HANDOVER_ISSUED_2). Never carries a PIN.
  final String? eventType;

  /// The rider's invitations changed; re-read them from the API.
  final bool offersChanged;

  /// A group order changed (members, cart, proposal); re-read it from the API.
  final String? groupId;

  /// Restaurant: group price requests changed for one of your outlets.
  final bool groupProposalsChanged;
  const LiveOrderUpdate(
    this.connection, {
    this.orderId,
    this.reconcile = false,
    this.eventType,
    this.offersChanged = false,
    this.groupId,
    this.groupProposalsChanged = false,
  });

  bool get isHandoverIssued =>
      eventType?.startsWith('HANDOVER_ISSUED') ?? false;
}

class EventVersions {
  final versions = <String, int>{};
  bool accept(Json event) {
    final id = event['orderId'], version = event['version'];
    if (id is! String ||
        version is! int ||
        version < 1 ||
        version <= (versions[id] ?? 0)) {
      return false;
    }
    versions[id] = version;
    return true;
  }
}

class _Lifecycle extends WidgetsBindingObserver {
  final void Function(AppLifecycleState) change;
  _Lifecycle(this.change);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => change(state);
}

final liveOrdersProvider = StreamProvider<LiveOrderUpdate>((ref) {
  final session = ref.watch(authProvider).asData?.value;
  final vault = ref.watch(sessionVaultProvider);
  if (session == null || vault.token == null) {
    return Stream.value(const LiveOrderUpdate('Offline · refresh available'));
  }
  final controller = StreamController<LiveOrderUpdate>();
  final versions = EventVersions();
  final base = Uri.parse(
    ref.watch(authenticatedClientProvider).options.baseUrl,
  );
  final socket = io.io(
    base.origin,
    io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew()
        .setAuth({'token': vault.token})
        .setReconnectionAttempts(5)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(10000)
        .build(),
  );
  bool closed = false;
  void emit(LiveOrderUpdate update) {
    if (!closed) controller.add(update);
  }

  socket.onConnect((_) {
    emit(const LiveOrderUpdate('Live updates connected', reconcile: true));
  });
  socket.onDisconnect((_) {
    emit(const LiveOrderUpdate('Live updates paused · pull to refresh'));
  });
  socket.onConnectError((_) {
    emit(
      const LiveOrderUpdate('Live sync waiting to reconnect · pull to refresh'),
    );
  });
  socket.onError((_) {
    emit(
      const LiveOrderUpdate('Live sync waiting to reconnect · pull to refresh'),
    );
  });
  socket.on('error', (_) {
    emit(
      const LiveOrderUpdate('Live sync waiting to reconnect · pull to refresh'),
    );
  });
  socket.on('reconnect', (_) {
    emit(const LiveOrderUpdate('Live updates connected', reconcile: true));
  });
  socket.on('reconnect_attempt', (_) {
    emit(const LiveOrderUpdate('Reconnecting live updates…'));
  });
  final seenEvents = <String>{};
  socket.on('order.updated', (dynamic raw) {
    if (raw is Map) {
      final event = Json.from(raw);
      final type = event['eventType'] as String?;
      // OTP issuance / arrival do not change the order version; de-duplicate
      // them by event id instead of dropping them as "not newer".
      final versionless =
          type != null &&
          (type.startsWith('HANDOVER_ISSUED') || type == 'RIDER_ARRIVED');
      final fresh = versionless
          ? (event['eventId'] is String &&
                seenEvents.add(event['eventId'] as String))
          : versions.accept(event);
      if (fresh) {
        emit(
          LiveOrderUpdate(
            'Live updates connected',
            orderId: event['orderId'] as String?,
            eventType: type,
          ),
        );
      }
    }
  });
  socket.on('group.updated', (dynamic raw) {
    emit(
      LiveOrderUpdate(
        'Live updates connected',
        groupId: raw is Map ? raw['groupId'] as String? : null,
        eventType: raw is Map ? raw['event'] as String? : null,
      ),
    );
  });
  socket.on('group.proposals', (dynamic raw) {
    emit(
      LiveOrderUpdate(
        'Live updates connected',
        groupId: raw is Map ? raw['groupId'] as String? : null,
        eventType: raw is Map ? raw['event'] as String? : null,
        groupProposalsChanged: true,
      ),
    );
  });
  socket.on('delivery.offers', (dynamic raw) {
    emit(
      LiveOrderUpdate(
        'Live updates connected',
        orderId: raw is Map ? raw['orderId'] as String? : null,
        offersChanged: true,
      ),
    );
  });
  final lifecycle = _Lifecycle((state) {
    if (state == AppLifecycleState.resumed) {
      socket.connect();
      emit(const LiveOrderUpdate('Reconnecting', reconcile: true));
    } else if (state == AppLifecycleState.paused) {
      socket.disconnect();
    }
  });
  WidgetsBinding.instance.addObserver(lifecycle);
  final subscription = vault.changes.stream.listen((_) {
    socket.disconnect();
  });
  ref.onDispose(() {
    closed = true;
    subscription.cancel();
    WidgetsBinding.instance.removeObserver(lifecycle);
    socket.dispose();
    controller.close();
  });
  socket.connect();
  return controller.stream;
});

/// Live messages invalidate REST snapshots; they never mutate displayed status.
class LiveOrderBar extends ConsumerWidget {
  final String path;
  final String? orderId;
  const LiveOrderBar({super.key, required this.path, this.orderId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(liveOrdersProvider, (_, next) {
      final event = next.asData?.value;
      if (event != null &&
          (event.reconcile ||
              event.orderId != null &&
                  (orderId == null || orderId == event.orderId))) {
        ref.invalidate(commerceReadProvider(path));
        final message = switch (event.eventType) {
          'SCHEDULE_AT_RISK' => 'A scheduled order is at risk of delay. Check its latest progress.',
          'SCHEDULE_DELAYED' => 'A scheduled delivery has missed its target window. View order details for updates.',
          'SCHEDULE_PREPARATION_DUE' => 'Scheduled preparation time has arrived.',
          _ => null,
        };
        if (message != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
            }
          });
        }

      }
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(liveOrdersProvider).asData?.value;
    final connection = state?.connection ?? 'Connecting live updates…';
    final isConnected = connection.contains('connected');
    final isReconnecting =
        connection.contains('Reconnecting') ||
        connection.contains('Connecting');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected
            ? scheme.secondaryContainer.withValues(alpha: 0.25)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (isConnected)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            )
          else if (isReconnecting)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.sync, size: 14, color: scheme.tertiary),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.sync, size: 14, color: scheme.onSurfaceVariant),
            ),
          Expanded(
            child: Text(
              isConnected ? 'Real-time sync active' : connection,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isConnected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
                fontWeight: isConnected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh latest status',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              ref.invalidate(commerceReadProvider(path));
              ref.invalidate(liveOrdersProvider);
            },
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      ),
    );
  }
}

class OrderTimeline extends StatelessWidget {
  final Json order;
  const OrderTimeline({super.key, required this.order});
  @override
  Widget build(BuildContext context) {
    final events = (order['events'] as List? ?? []).cast<Map>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order timeline',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final event in events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(eventLabel(event['eventType'] as String)),
                    ),
                    Text(
                      _time(event['createdAt'] as String),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (order['rejectionReason'] != null)
              Text('Reason: ${order['rejectionReason']}'),
            if (order['refundReviewRequired'] == true)
              const Text(
                'Payment reconciliation required. Refund is not yet confirmed.',
              ),
          ],
        ),
      ),
    );
  }

  String _time(String value) {
    final d = DateTime.parse(value).toLocal();
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

String eventLabel(String value) =>
    const {
      'SCHEDULE_PREPARATION_DUE': 'Scheduled preparation should begin',
      'SCHEDULE_AT_RISK': 'Delivery target at risk of delay',
      'SCHEDULE_DELAYED': 'Delivery target window missed',
      'SCHEDULE_DISPATCH_DUE': 'Scheduled rider invitations released',
      'SCHEDULE_CANCELED': 'Scheduled order canceled',
      'ORDER_CREATED': 'Order recorded',
      'PAYMENT_CAPTURED': 'Test payment confirmed',
      'ORDER_ACCEPTED': 'Restaurant accepted',
      'ORDER_REJECTED': 'Restaurant declined',
      'PREPARATION_STARTED': 'Kitchen preparing',
      'ORDER_READY': 'Ready for pickup',
      'RIDER_ASSIGNED': 'Delivery partner assigned',
      'RIDER_ARRIVED': 'Delivery partner arrived',
      'ORDER_PICKED_UP': 'Picked up',
      'OUT_FOR_DELIVERY': 'Out for delivery',
      'ORDER_DELIVERED': 'Delivered',
    }[value] ??
    (value.startsWith('HANDOVER_ISSUED')
        ? 'Delivery OTP issued'
        : 'Order updated');
