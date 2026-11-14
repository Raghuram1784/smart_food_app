import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'commerce_repository.dart';
import 'live_orders.dart';

const _liveStatuses = {'READY_FOR_PICKUP', 'PICKED_UP', 'OUT_FOR_DELIVERY'};

/// One global, customer-only delivery-OTP popup.
///
/// This widget sits in `MaterialApp.router(builder:)`, i.e. *above* the root
/// Navigator. It therefore never renders the popup itself (there is no Overlay
/// there — that was the "No Overlay widget found" crash). Instead it inserts a
/// single [OverlayEntry] into the root Navigator's own Overlay, so tooltips,
/// ink and focus work and the popup floats above every route.
///
/// Hydration: on customer login/restore and on every socket (re)connect it reads
/// the customer's active orders and their OTP from the authorized customer API.
/// Socket events carry no PIN; reading never issues a new code. A dismissed code
/// is remembered per customer and stays available in Order Details.
/// Limitation: Socket.IO cannot raise OS notifications for a backgrounded or
/// terminated app; the popup appears when the app is reopened.
class CustomerOtpLayer extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final void Function(String orderId) onOpenOrder;
  const CustomerOtpLayer({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.onOpenOrder,
  });

  @override
  ConsumerState<CustomerOtpLayer> createState() => _CustomerOtpLayerState();
}

class ActiveOtp {
  final String orderId;
  final String orderNumber;
  final String pin;
  final int challengeVersion;
  final DateTime? expiresAt;
  const ActiveOtp(this.orderId, this.orderNumber, this.pin, this.challengeVersion, this.expiresAt);
  String get key => '$orderId:$challengeVersion';
}

class _CustomerOtpLayerState extends ConsumerState<CustomerOtpLayer> {
  ActiveOtp? _otp;
  String? _customer;
  bool _copied = false;
  Timer? _tick;
  OverlayEntry? _entry;
  bool _syncScheduled = false;
  final _inFlight = <String>{};
  ProviderSubscription<String?>? _customerSub;

  @override
  void initState() {
    super.initState();
    // React to login / logout / account switch outside of build.
    _customerSub = ref.listenManual<String?>(customerIdProvider, (_, next) {
      if (next == _customer) return;
      _customer = next;
      _setOtp(null); // never carry an OTP across accounts or roles
      if (next != null) unawaited(_scanActive());
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _customerSub?.close();
    _tick?.cancel();
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    super.dispose();
  }

  // ---- state -> overlay sync (never during build) --------------------------

  void _setOtp(ActiveOtp? otp) {
    _otp = otp;
    _copied = false;
    _tick?.cancel();
    if (otp != null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _entry?.markNeedsBuild());
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled || !mounted) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      _sync();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _sync() {
    if (!mounted) return;
    if (_otp == null) {
      _entry?.remove();
      _entry?.dispose();
      _entry = null;
      return;
    }
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = widget.navigatorKey.currentState?.overlay;
    if (overlay == null) {
      _scheduleSync(); // navigator not built yet; try next frame
      return;
    }
    _entry = OverlayEntry(builder: _buildPopup);
    overlay.insert(_entry!);
  }

  Widget _buildPopup(BuildContext context) {
    final otp = _otp;
    if (otp == null) return const SizedBox.shrink();
    return OtpPopup(
      otp: otp,
      copied: _copied,
      onCopy: () {
        unawaited(Clipboard.setData(ClipboardData(text: otp.pin)));
        _copied = true;
        _entry?.markNeedsBuild();
      },
      onDismiss: _dismiss,
      onOpen: () {
        _dismiss();
        widget.onOpenOrder(otp.orderId);
      },
    );
  }

  // ---- data -------------------------------------------------------------------

  String? get _seenKey => _customer == null ? null : 'otp_seen_$_customer';

  Set<String> _seen() {
    try {
      final k = _seenKey;
      return k == null ? {} : (ref.read(preferencesProvider).getStringList(k) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _markSeen(String key) async {
    final k = _seenKey;
    if (k == null) return;
    try {
      final list = [..._seen(), key];
      await ref.read(preferencesProvider).setStringList(k, list.length > 50 ? list.sublist(list.length - 50) : list);
    } catch (_) {}
  }

  Future<void> _check(String orderId) async {
    final customer = _customer;
    if (customer == null || !_inFlight.add(orderId)) return;
    try {
      final repo = ref.read(commerceRepositoryProvider);
      final h = await repo.request('GET', 'orders/$orderId/handover');
      // The account may have changed while waiting: discard stale results.
      if (!mounted || customer != _customer || h is! Map) return;
      final pin = h['pin'], version = h['challengeVersion'];
      if (h['state'] != 'ACTIVE' || pin is! String || version is! int) {
        if (_otp?.orderId == orderId) _setOtp(null);
        return;
      }
      final key = '$orderId:$version';
      if (_seen().contains(key) || _otp?.key == key) return;
      final order = await repo.request('GET', 'orders/$orderId');
      if (!mounted || customer != _customer) return;
      final number = order is Map ? order['orderNumber'] as String? ?? '' : '';
      _setOtp(ActiveOtp(orderId, number, pin, version, DateTime.tryParse('${h['expiresAt']}')?.toLocal()));
    } catch (_) {
      // Unauthorized / not found / offline: show nothing rather than a guess.
    } finally {
      _inFlight.remove(orderId);
    }
  }

  Future<void> _scanActive() async {
    final customer = _customer;
    if (customer == null) return;
    try {
      final raw = await ref.read(commerceRepositoryProvider).request('GET', 'orders?page=1');
      if (customer != _customer) return;
      final items = (raw is Map ? raw['items'] : null) as List? ?? const [];
      for (final o in items) {
        if (o is Map && _liveStatuses.contains(o['status']) && o['id'] is String) {
          await _check(o['id'] as String);
        }
      }
    } catch (_) {}
  }

  void _dismiss() {
    final otp = _otp;
    if (otp != null) unawaited(_markSeen(otp.key));
    _setOtp(null);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveOrdersProvider, (_, next) {
      final e = next.asData?.value;
      if (e == null || _customer == null) return;
      if (e.reconcile) {
        unawaited(_scanActive());
      } else if (e.orderId != null && (e.isHandoverIssued || e.eventType == 'RIDER_ASSIGNED')) {
        unawaited(_check(e.orderId!));
      } else if (e.orderId != null && e.orderId == _otp?.orderId && e.eventType == 'ORDER_DELIVERED') {
        _setOtp(null);
      }
    });
    return widget.child;
  }
}

/// Compact, dismissible top card. Fits narrow phones and large text scales;
/// it does not block the rest of the screen.
class OtpPopup extends StatelessWidget {
  final ActiveOtp otp;
  final bool copied;
  final VoidCallback onCopy, onDismiss, onOpen;
  const OtpPopup({
    super.key,
    required this.otp,
    required this.copied,
    required this.onCopy,
    required this.onDismiss,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final left = otp.expiresAt?.difference(DateTime.now());
    final expired = left != null && left.isNegative;
    final expiry = left == null
        ? ''
        : expired
            ? 'Expired. Your delivery partner will request a new code on arrival.'
            : 'Valid for ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 480, maxHeight: maxHeight),
          child: Material(
            key: const ValueKey('customer-otp-popup'),
            elevation: 10,
            borderRadius: BorderRadius.circular(22),
            color: scheme.surface,
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 10, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(Icons.lock_outline, color: scheme.primary, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your Delivery OTP',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(tooltip: 'Dismiss', onPressed: onDismiss, icon: const Icon(Icons.close)),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      children: [
                        if (otp.orderNumber.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Order ${otp.orderNumber}',
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(height: 8),
                        // Scales down instead of overflowing on narrow screens / large text.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Semantics(
                            label: 'Delivery OTP ${otp.pin.split('').join(' ')}',
                            child: Text(
                              otp.pin,
                              style: theme.textTheme.displaySmall?.copyWith(
                                letterSpacing: 8,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [FontFeature.tabularFigures()],
                                color: expired ? scheme.outline : scheme.primary,
                              ),
                            ),
                          ),
                        ),
                        if (expiry.isNotEmpty)
                          Text(
                            expiry,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(color: expired ? scheme.error : scheme.onSurfaceVariant),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Share this code only when you receive your food. Never share it on a call or message.',
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: onCopy,
                              icon: Icon(copied ? Icons.check : Icons.copy, size: 18),
                              label: Text(copied ? 'Copied' : 'Copy OTP'),
                            ),
                            FilledButton(onPressed: onOpen, child: const Text('View order')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
