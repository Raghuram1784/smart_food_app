import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rider_location_sharing.dart';

/// Shown on the rider's active delivery. Sharing starts automatically only when location is
/// already allowed; otherwise the rider taps to allow it. Never blocks delivery actions.
class RiderTrackingPanel extends ConsumerStatefulWidget {
  final String orderId;
  const RiderTrackingPanel({super.key, required this.orderId});
  @override
  ConsumerState<RiderTrackingPanel> createState() => _RiderTrackingPanelState();
}

class _RiderTrackingPanelState extends ConsumerState<RiderTrackingPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoStart());
  }

  @override
  void didUpdateWidget(RiderTrackingPanel old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId) WidgetsBinding.instance.addPostFrameCallback((_) => _autoStart());
  }

  void _autoStart() {
    if (!mounted) return;
    final s = ref.read(riderLocationSharingProvider);
    if (s.orderId == widget.orderId && (s.active || s.status == SharingStatus.permissionDeniedForever)) return;
    ref.read(riderLocationSharingProvider.notifier).start(widget.orderId, ask: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final s = ref.watch(riderLocationSharingProvider);
    final mine = s.orderId == widget.orderId;
    final sharing = mine && s.status == SharingStatus.sharing && s.lastSentAt != null;
    final (icon, color, title) = switch (mine ? s.status : SharingStatus.idle) {
      SharingStatus.sharing => s.lastSentAt != null ? (Icons.my_location, Colors.green.shade700, 'Sharing live location') : (Icons.gps_not_fixed, scheme.primary, 'Getting GPS fix…'),
      SharingStatus.starting => (Icons.gps_not_fixed, scheme.primary, 'Starting location sharing…'),
      SharingStatus.permissionDenied => (Icons.location_disabled, scheme.error, 'Location not allowed'),
      SharingStatus.permissionDeniedForever => (Icons.location_disabled, scheme.error, 'Location blocked in Settings'),
      SharingStatus.serviceDisabled => (Icons.location_off, scheme.error, 'Location (GPS) is off'),
      SharingStatus.error => (Icons.gps_off, scheme.error, 'Location temporarily unavailable'),
      _ => (Icons.share_location, scheme.primary, 'Live location is off'),
    };
    final ago = s.lastSentAt == null ? null : DateTime.now().difference(s.lastSentAt!).inSeconds;
    return Card(
      key: const ValueKey('rider-tracking-panel'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(title, key: const ValueKey('rider-tracking-title'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            if (sharing && s.lastAccuracy != null) Text('±${s.lastAccuracy!.round()} m', style: theme.textTheme.labelMedium),
          ]),
          const SizedBox(height: 4),
          Text(
            mine && s.message != null
                ? s.message!
                : sharing
                    ? 'Your customer can follow this delivery${ago != null ? ' · sent ${ago}s ago' : ''}. Stops automatically after OTP delivery.'
                    : 'Share your location while this delivery is active so your customer sees you on the map. Delivery works either way.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (!(mine && s.active)) ...[
            const SizedBox(height: 10),
            if (mine && (s.status == SharingStatus.permissionDeniedForever || s.status == SharingStatus.serviceDisabled))
              OutlinedButton.icon(
                key: const ValueKey('rider-tracking-settings'),
                onPressed: () => ref.read(riderLocationSharingProvider.notifier).openSettings(),
                icon: const Icon(Icons.settings),
                label: Text(s.status == SharingStatus.serviceDisabled ? 'Open location settings' : 'Open app settings'),
              )
            else
              FilledButton.icon(
                key: const ValueKey('rider-tracking-start'),
                onPressed: () => ref.read(riderLocationSharingProvider.notifier).start(widget.orderId),
                icon: const Icon(Icons.share_location),
                label: const Text('Share live location'),
              ),
          ],
        ]),
      ),
    );
  }
}
