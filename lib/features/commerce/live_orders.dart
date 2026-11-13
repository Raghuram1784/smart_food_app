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
  const LiveOrderUpdate(
    this.connection, {
    this.orderId,
    this.reconcile = false,
  });
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
    emit(const LiveOrderUpdate('Offline · refresh available'));
  });
  socket.onConnectError((_) {
    emit(const LiveOrderUpdate('Connection unavailable · refresh or retry'));
  });
  socket.on('order.updated', (dynamic raw) {
    if (raw is Map) {
      final event = Json.from(raw);
      if (versions.accept(event)) {
        emit(
          LiveOrderUpdate('Live updates connected', orderId: event['orderId']),
        );
      }
    }
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
      }
    });
    final state = ref.watch(liveOrdersProvider).asData?.value;
    return Row(
      children: [
        Expanded(
          child: Text(
            state?.connection ?? 'Connecting live updates',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          tooltip: 'Refresh order status',
          onPressed: () {
            ref.invalidate(commerceReadProvider(path));
            ref.invalidate(liveOrdersProvider);
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
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
      'ORDER_CREATED': 'Order recorded',
      'PAYMENT_CAPTURED': 'Test payment confirmed',
      'ORDER_ACCEPTED': 'Restaurant accepted',
      'ORDER_REJECTED': 'Restaurant declined',
      'PREPARATION_STARTED': 'Kitchen preparing',
      'ORDER_READY': 'Ready for pickup',
      'RIDER_ASSIGNED': 'Delivery partner assigned',
      'ORDER_PICKED_UP': 'Picked up',
      'OUT_FOR_DELIVERY': 'Out for delivery',
      'ORDER_DELIVERED': 'Delivered',
    }[value] ??
    'Order updated';
