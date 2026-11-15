import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'commerce_repository.dart';

/// Checkout callbacks are evidence to verify, never authority to mark paid.
class PaymentPanel extends ConsumerStatefulWidget {
  final String orderId;
  const PaymentPanel({super.key, required this.orderId});
  @override
  ConsumerState<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends ConsumerState<PaymentPanel>
    with WidgetsBindingObserver {
  Razorpay? checkout;
  Json? status;
  String? attemptId, customerId, message;
  bool busy = false;
  bool get active => mounted && customerId == ref.read(customerIdProvider);
  CommerceRepository get repo => ref.read(commerceRepositoryProvider);

  @override
  void initState() {
    super.initState();
    customerId = ref.read(customerIdProvider);
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(refresh);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) refresh();
  }

  Future<void> refresh() async {
    if (!active) return;
    try {
      final result = Json.from(
        await repo.request('GET', 'payments/orders/${widget.orderId}/status'),
      );
      if (!active) return;
      final previous = status?['paymentStatus'];
      setState(() => status = result);
      if (previous != null &&
          previous != 'PAID' &&
          result['paymentStatus'] == 'PAID') {
        ref.invalidate(commerceReadProvider('orders/${widget.orderId}'));
      }
    } catch (e) {
      if (active) setState(() => message = commerceError(e));
    }
  }

  Future<void> pay() async {
    if (busy || !active) return;
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      setState(
        () => message = 'Open this order in the Android or iOS app to use Razorpay Test Checkout.',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final config = Json.from(
        await repo.request('POST', 'payments/razorpay/create-order', {
          'orderId': widget.orderId,
        }),
      );
      if (!active) return;
      attemptId = config['attemptId'] as String;
      checkout?.clear();
      checkout = Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, verified)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, cancelled)
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, externalWallet);
      checkout!.open({
        'key': config['keyId'],
        'order_id': config['providerOrderId'],
        'amount': config['amount'],
        'currency': config['currency'],
        'name': 'SAMORI · TEST',
        'description': 'Test payment only',
        'retry': {'enabled': false},
      });
    } catch (e) {
      if (active) {
        setState(() {
          busy = false;
          message = commerceError(e);
        });
      }
      await refresh();
    }
  }

  Future<void> verified(PaymentSuccessResponse response) async {
    if (!active || attemptId == null) return;
    try {
      final result = Json.from(
        await repo.request('POST', 'payments/razorpay/verify', {
          'attemptId': attemptId,
          'razorpay_order_id': response.orderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
        }),
      );
      if (active) {
        setState(() {
          status = result;
          message = null;
        });
        if (result['paymentStatus'] == 'PAID') {
          ref.invalidate(commerceReadProvider('orders/${widget.orderId}'));
        }
      }
    } catch (e) {
      if (active) setState(() => message = commerceError(e));
    } finally {
      if (active) setState(() => busy = false);
      await refresh();
    }
  }

  Future<void> cancelled(PaymentFailureResponse response) async {
    if (!active) return;
    setState(() {
      busy = false;
      message =
          'Checkout closed or payment failed. Check status before retrying.';
    });
    await refresh();
  }

  Future<void> externalWallet(ExternalWalletResponse response) async {
    if (!active) return;
    setState(() {
      busy = false;
      message = 'Awaiting payment confirmation. Check status.';
    });
    await refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    checkout?.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paid = status?['paymentStatus'] == 'PAID';
    final authorized = status?['paymentStatus'] == 'PAYMENT_AUTHORIZED';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Razorpay Test Mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              paid
                  ? 'Test payment confirmed. Awaiting restaurant action.'
                  : authorized
                  ? 'Authorized. Waiting for capture; do not pay again.'
                  : 'No real money is collected. Payment is confirmed by our server.',
            ),
            if (status?['verificationPending'] == true)
              const Text('Verification pending. Check status before retrying.'),
            if (message != null) Text(message!),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                if (!paid && !authorized)
                  FilledButton(
                    onPressed: busy ? null : pay,
                    child: Text(
                      busy ? 'Checking payment…' : 'Pay with Razorpay TEST',
                    ),
                  ),
                TextButton(
                  onPressed: busy ? null : refresh,
                  child: const Text('Check payment status'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
