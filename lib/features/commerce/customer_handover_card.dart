import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import 'commerce_repository.dart';

class CustomerHandoverCard extends ConsumerStatefulWidget {
  final Json order;
  final VoidCallback? onHandoverChanged;

  const CustomerHandoverCard({
    super.key,
    required this.order,
    this.onHandoverChanged,
  });

  @override
  ConsumerState<CustomerHandoverCard> createState() =>
      _CustomerHandoverCardState();
}

class _CustomerHandoverCardState extends ConsumerState<CustomerHandoverCard> {
  Json? _handover;
  bool _loading = false;
  bool _issuing = false;
  String? _error;
  Timer? _countdownTimer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _checkAndFetch();
  }

  @override
  void didUpdateWidget(covariant CustomerHandoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order['status'] != widget.order['status'] ||
        oldWidget.order['version'] != widget.order['version']) {
      _checkAndFetch();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  bool get _isRelevant {
    final status = widget.order['status'];
    return status == 'OUT_FOR_DELIVERY' || status == 'DELIVERED';
  }

  Future<void> _checkAndFetch() async {
    if (!_isRelevant) return;
    await _fetchHandover(silent: _handover != null);
  }

  Future<void> _fetchHandover({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await ref
          .read(commerceRepositoryProvider)
          .request('GET', 'orders/${widget.order['id']}/handover');
      if (mounted) {
        setState(() {
          _handover = res is Map ? Json.from(res) : null;
          _loading = false;
          _error = null;
        });
        _setupTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = commerceError(e);
        });
      }
    }
  }

  Future<void> _issuePin() async {
    if (_issuing) return;
    setState(() {
      _issuing = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(commerceRepositoryProvider)
          .request('POST', 'orders/${widget.order['id']}/handover/issue');
      if (mounted) {
        setState(() {
          _handover = res is Map ? Json.from(res) : null;
          _issuing = false;
          _error = null;
        });
        _setupTimer();
        widget.onHandoverChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _issuing = false;
          _error = commerceError(e);
        });
      }
    }
  }

  void _setupTimer() {
    _countdownTimer?.cancel();
    final expiresAt = _handover?['expiresAt'] as String?;
    if (_handover?['state'] == 'ACTIVE' && expiresAt != null) {
      final expiry = DateTime.tryParse(expiresAt)?.toLocal();
      if (expiry != null) {
        final diff = expiry.difference(DateTime.now()).inSeconds;
        _secondsRemaining = max(0, diff);
        if (_secondsRemaining > 0) {
          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            if (_secondsRemaining > 1) {
              setState(() => _secondsRemaining--);
            } else {
              timer.cancel();
              setState(() => _secondsRemaining = 0);
              _fetchHandover(silent: true);
            }
          });
        }
      }
    }
  }

  String _formatTimer(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRelevant) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final culinary = theme.extension<CulinaryColors>();

    // Handover verified & order delivered
    if (widget.order['status'] == 'DELIVERED' ||
        _handover?['state'] == 'CONSUMED') {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (culinary?.pistachio ?? scheme.secondaryContainer).withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (culinary?.pistachio ?? scheme.secondary).withValues(
              alpha: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.verified_rounded,
              color: culinary?.pistachio ?? scheme.primary,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Handover verified',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Order safely delivered with 6-digit PIN verification.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // While loading initially with no cached data
    if (_loading && _handover == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: const Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final state = (_handover?['state'] as String?) ?? 'NOT_ISSUED';
    final pin = _handover?['pin'] as String?;
    final canIssue = _handover?['canIssue'] == true;
    final issuesRemaining = (_handover?['issuesRemaining'] as int?) ?? 5;
    final attemptsRemaining = (_handover?['attemptsRemaining'] as int?) ?? 5;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: state == 'ACTIVE'
              ? scheme.primary.withValues(alpha: 0.6)
              : state == 'LOCKED'
              ? scheme.error.withValues(alpha: 0.6)
              : scheme.outlineVariant,
          width: state == 'ACTIVE' ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: state == 'ACTIVE'
                        ? scheme.primaryContainer
                        : state == 'LOCKED'
                        ? scheme.errorContainer
                        : scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    state == 'ACTIVE'
                        ? Icons.pin_outlined
                        : state == 'LOCKED'
                        ? Icons.lock_outline
                        : state == 'EXPIRED'
                        ? Icons.timer_off_outlined
                        : Icons.shield_outlined,
                    size: 20,
                    color: state == 'ACTIVE'
                        ? scheme.primary
                        : state == 'LOCKED'
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secure delivery handover',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        state == 'ACTIVE'
                            ? 'Share this PIN with your rider upon arrival'
                            : state == 'NOT_ISSUED'
                            ? 'PIN required to receive your food'
                            : state == 'EXPIRED'
                            ? 'PIN expired · Refresh required'
                            : state == 'LOCKED'
                            ? 'Handover locked (too many attempts)'
                            : 'Handover verification',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StateBadge(state: state),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Main State-dependent Body
            if (state == 'ACTIVE' && pin != null) ...[
              // PIN presentation box
              Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        pin,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          letterSpacing: 10,
                          fontWeight: FontWeight.w900,
                          color: scheme.primary,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: _secondsRemaining < 60
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Expires in ${_formatTimer(_secondsRemaining)}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: _secondsRemaining < 60
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            '$attemptsRemaining attempts left',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Do not share this PIN over phone or message. Only read it aloud after the delivery partner hands you your sealed package.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (canIssue) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _issuing ? null : _issuePin,
                    icon: _issuing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(
                      'Regenerate PIN ($issuesRemaining remaining)',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ),
              ],
            ] else if (state == 'NOT_ISSUED') ...[
              Text(
                'Your meal is out for delivery! An authoritative 6-digit PIN ensures only you can receive your order from the delivery partner.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _issuing ? null : _issuePin,
                  icon: _issuing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.pin_outlined),
                  label: const Text('Generate delivery PIN'),
                ),
              ),
            ] else if (state == 'EXPIRED') ...[
              Text(
                'The previous 6-digit delivery PIN expired. Request a new PIN to give to your delivery partner.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (canIssue) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _issuing ? null : _issuePin,
                    icon: _issuing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Request new delivery PIN'),
                  ),
                ),
              ] else ...[
                Text(
                  'Issuance limit reached or cooldown active. Please wait or contact support.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
            ] else if (state == 'LOCKED') ...[
              Text(
                'Handover was locked after 5 incorrect PIN entries for security. Please wait for the lockout cooldown period to pass before generating a new PIN.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _fetchHandover(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Check status'),
              ),
            ] else if (state == 'INVALIDATED') ...[
              Text(
                'A new delivery partner was assigned to this order. Please generate a fresh PIN for the new rider.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (canIssue) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _issuing ? null : _issuePin,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Generate new PIN'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final String state;
  const _StateBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final culinary = theme.extension<CulinaryColors>();

    Color bg;
    Color fg;
    String label;

    switch (state) {
      case 'ACTIVE':
        bg = (culinary?.pistachio ?? scheme.secondaryContainer).withValues(
          alpha: 0.8,
        );
        fg = scheme.onSecondaryContainer;
        label = 'Active';
        break;
      case 'EXPIRED':
        bg = Colors.amber.withValues(alpha: 0.2);
        fg = Colors.amber[900]!;
        label = 'Expired';
        break;
      case 'LOCKED':
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        label = 'Locked';
        break;
      case 'INVALIDATED':
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        label = 'Reassigned';
        break;
      case 'CONSUMED':
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
        label = 'Verified';
        break;
      default:
        bg = scheme.primaryContainer;
        fg = scheme.onPrimaryContainer;
        label = 'Ready';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
