import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../commerce/commerce_repository.dart';
import '../commerce/live_orders.dart';
import '../finder/finder_theme.dart';
import '../location/location_picker_screen.dart';
import 'tracking_api.dart';

/// Map tiles are configurable. The OpenStreetMap default is for light development testing only
/// (tile usage policy + attribution); set MAP_TILE_URL to an approved provider for deployment.
const mapTileUrl = String.fromEnvironment('MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
const mapAttribution = String.fromEnvironment('MAP_ATTRIBUTION', defaultValue: 'OpenStreetMap contributors');

/// Pure freshness rule shared by the screen and tests (server sends the thresholds).
String fixFreshness(DateTime? recordedAt, DateTime now, {int liveSeconds = 30, int unavailableSeconds = 120}) {
  if (recordedAt == null) return 'WAITING';
  final age = now.difference(recordedAt).inSeconds;
  return age <= liveSeconds ? 'LIVE' : age <= unavailableSeconds ? 'STALE' : 'UNAVAILABLE';
}

String agoText(int seconds) => seconds < 60 ? '$seconds seconds ago' : seconds < 3600 ? '${seconds ~/ 60} min ago' : '${seconds ~/ 3600} h ago';

class TrackOrderScreen extends ConsumerStatefulWidget {
  final String orderId;
  const TrackOrderScreen({super.key, required this.orderId});
  @override
  ConsumerState<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends ConsumerState<TrackOrderScreen> with SingleTickerProviderStateMixin {
  Json? data;
  Object? error;
  bool loading = true;
  String connection = 'Connecting live updates…';
  final MapController map = MapController();
  bool mapReady = false, fitted = false, following = true;
  Duration clockOffset = Duration.zero; // server time minus device time
  // Display-only marker animation between two REAL fixes (no invented positions are stored or sent).
  late final AnimationController anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  LatLng? from, to;
  DateTime? riderRecordedAt;
  double? heading;
  Timer? ticker, poll;

  @override
  void initState() {
    super.initState();
    anim.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (following && mapReady && fitted && riderPoint != null && anim.isAnimating) {
        // Gentle follow without fighting the user's own panning.
        try {
          map.move(riderPoint!, map.camera.zoom);
        } catch (_) {}
      }
    });
    _load();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    poll = Timer.periodic(const Duration(seconds: 20), (_) => _load(quiet: true)); // ETA refresh + safety net
  }

  @override
  void dispose() {
    ticker?.cancel();
    poll?.cancel();
    anim.dispose();
    map.dispose();
    super.dispose();
  }

  LatLng? get riderPoint {
    if (to == null) return null;
    if (from == null) return to;
    final t = Curves.easeInOut.transform(anim.value);
    return LatLng(from!.latitude + (to!.latitude - from!.latitude) * t, from!.longitude + (to!.longitude - from!.longitude) * t);
  }

  DateTime get serverNow => DateTime.now().add(clockOffset);

  Future<void> _load({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => loading = data == null);
    try {
      final d = await ref.read(trackingApiProvider).view(widget.orderId);
      if (!mounted) return;
      final server = DateTime.tryParse(d['serverTime'] as String? ?? '');
      if (server != null) clockOffset = server.difference(DateTime.now());
      setState(() {
        data = d;
        error = null;
        loading = false;
      });
      final loc = (d['rider'] as Map?)?['location'] as Map?;
      if (loc != null) {
        _applyFix(Map<String, dynamic>.from(loc));
      } else if (d['terminal'] == true || (d['rider'] as Map?)?['freshness'] == 'WAITING') {
        setState(() {
          to = null;
          from = null;
          riderRecordedAt = null;
        });
      }
      _fitIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  void _applyFix(Map<String, dynamic> loc) {
    final lat = (loc['latitude'] as num?)?.toDouble(), lng = (loc['longitude'] as num?)?.toDouble();
    final at = DateTime.tryParse(loc['recordedAt']?.toString() ?? '');
    if (lat == null || lng == null || at == null) return;
    if (riderRecordedAt != null && !at.isAfter(riderRecordedAt!)) return; // ignore duplicates / out-of-order
    final next = LatLng(lat, lng);
    setState(() {
      from = riderPoint ?? next;
      to = next;
      riderRecordedAt = at;
      heading = (loc['headingDegrees'] as num?)?.toDouble() ?? heading;
    });
    anim.forward(from: 0);
    _fitIfNeeded();
  }

  List<LatLng> get _points {
    final d = data;
    if (d == null) return const [];
    LatLng? p(Map? m) => m == null || m['latitude'] == null ? null : LatLng((m['latitude'] as num).toDouble(), (m['longitude'] as num).toDouble());
    return [?to, ?p((d['restaurant'] as Map?)?['location'] as Map?), ?p(d['destination'] as Map?)];
  }

  /// First fix / first data: frame everything once the map is ready (MapController is unusable before onMapReady).
  void _fitIfNeeded({bool force = false}) {
    if (!mapReady || !mounted || (fitted && !force)) return;
    final pts = _points;
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        map.move(pts.first, 15);
      } else {
        map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.fromLTRB(48, 120, 48, 60), maxZoom: 16.5));
      }
      fitted = true;
    } catch (_) {}
  }

  Future<void> _confirmPin() async {
    final picked = await Navigator.of(context).push<Object?>(MaterialPageRoute(builder: (_) => const LocationPickerScreen()));
    if (picked is! PickedLocation || !mounted) return;
    try {
      final d = await ref.read(trackingApiProvider).setDestination(widget.orderId, picked.latitude, picked.longitude);
      if (!mounted) return;
      setState(() => data = d);
      fitted = false;
      _fitIfNeeded();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(commerceError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveOrdersProvider, (_, next) {
      final u = next.asData?.value;
      if (u == null) return;
      if (u.connection != connection) setState(() => connection = u.connection);
      if (u.location != null && u.orderId == widget.orderId) {
        _applyFix(u.location!);
      } else if (u.reconcile || (u.orderId == widget.orderId && u.eventType != null)) {
        _load(quiet: true); // reconnect recovery and status changes re-read the authoritative view
      }
    });
    final c = FinderColors.of(context);
    final d = data;
    return Scaffold(
      backgroundColor: c.ivory,
      appBar: AppBar(
        backgroundColor: c.forest,
        foregroundColor: c.onForest,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Track order'),
          if (d != null) Text(d['orderNumber'] as String? ?? '', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onForest.withValues(alpha: .8))),
        ]),
        actions: [IconButton(tooltip: 'Refresh', onPressed: () => _load(), icon: const Icon(Icons.refresh))],
      ),
      body: d == null
          ? Center(child: loading ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(24), child: Text(error == null ? 'Tracking unavailable' : commerceError(error!), textAlign: TextAlign.center)))
          : Column(children: [
              Expanded(flex: 11, child: _mapArea(c, d)),
              Expanded(flex: 10, child: _details(c, d)),
            ]),
    );
  }

  Widget _mapArea(FinderColors c, Json d) {
    final pts = _points;
    final restaurant = (d['restaurant'] as Map?)?['location'] as Map?;
    final dest = d['destination'] as Map?;
    final route = (d['route'] as List?)?.map((p) => LatLng(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())).toList();
    final status = _riderStatus(d);
    if (pts.isEmpty) {
      return Container(
        key: const ValueKey('track-no-map'),
        color: c.paleGreen,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.map_outlined, size: 48, color: c.forest),
          const SizedBox(height: 8),
          Text(status.$2, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.forest, fontWeight: FontWeight.w800)),
          if (dest == null && d['terminal'] != true) ...[const SizedBox(height: 10), _pinButton()],
        ]),
      );
    }
    return Stack(children: [
      FlutterMap(
        key: const ValueKey('track-map'),
        mapController: map,
        options: MapOptions(
          initialCenter: pts.first,
          initialZoom: 14,
          onMapReady: () {
            mapReady = true;
            _fitIfNeeded();
          },
          onPositionChanged: (_, gesture) {
            if (gesture && following) setState(() => following = false);
          },
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          TileLayer(urlTemplate: mapTileUrl, userAgentPackageName: 'com.smartfood.app', maxZoom: 19),
          if (route != null && route.length > 1) PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 5, color: c.forest.withValues(alpha: .75))]),
          MarkerLayer(markers: [
            if (restaurant != null)
              Marker(point: LatLng((restaurant['latitude'] as num).toDouble(), (restaurant['longitude'] as num).toDouble()), width: 44, height: 44,
                  child: _pin(c.coral, Icons.storefront, 'Restaurant')),
            if (dest != null)
              Marker(point: LatLng((dest['latitude'] as num).toDouble(), (dest['longitude'] as num).toDouble()), width: 44, height: 44,
                  child: _pin(c.forest, Icons.home_rounded, 'Delivery location')),
            if (riderPoint != null)
              Marker(point: riderPoint!, width: 52, height: 52, child: _bike(c, status.$1 == 'LIVE')),
          ]),
          RichAttributionWidget(attributions: [TextSourceAttribution(mapAttribution)]),
        ],
      ),
      Positioned(top: 12, left: 12, right: 12, child: _statusChip(c, status)),
      Positioned(
        right: 12,
        bottom: 36,
        child: FloatingActionButton.small(
          key: const ValueKey('track-recenter'),
          heroTag: 'recenter',
          backgroundColor: c.card,
          foregroundColor: c.forest,
          tooltip: 'Recenter',
          onPressed: () {
            setState(() => following = true);
            _fitIfNeeded(force: true);
          },
          child: const Icon(Icons.center_focus_strong),
        ),
      ),
    ]);
  }

  Widget _pin(Color color, IconData icon, String label) => Semantics(
        label: label,
        child: Container(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)]),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );

  Widget _bike(FinderColors c, bool live) => Semantics(
        label: 'Delivery partner',
        child: Container(
          key: const ValueKey('rider-marker'),
          decoration: BoxDecoration(color: live ? c.gold : c.gold.withValues(alpha: .55), shape: BoxShape.circle, border: Border.all(color: c.forest, width: 3), boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)]),
          child: Transform.rotate(angle: heading == null ? 0 : (heading! - 90) * math.pi / 180, child: Icon(Icons.two_wheeler, color: c.forest, size: 26)),
        ),
      );

  /// (freshness, headline, detail)
  (String, String, String?) _riderStatus(Json d) {
    final rider = d['rider'] as Map?;
    if (d['terminal'] == true) return ('ENDED', d['status'] == 'DELIVERED' ? 'Delivered' : 'Tracking ended', null);
    if (rider == null) return ('WAITING', 'A delivery partner will be assigned when your food is ready', null);
    final rules = (d['rules'] as Map?) ?? const {};
    final f = fixFreshness(riderRecordedAt, serverNow, liveSeconds: (rules['liveSeconds'] as int?) ?? 30, unavailableSeconds: (rules['unavailableSeconds'] as int?) ?? 120);
    final age = riderRecordedAt == null ? null : math.max(0, serverNow.difference(riderRecordedAt!).inSeconds);
    return switch (f) {
      'LIVE' => ('LIVE', '${rider['name']} is on the way', 'Updated ${agoText(age!)}'),
      'STALE' => ('STALE', 'Rider location may be out of date', 'Last updated ${agoText(age!)}'),
      'UNAVAILABLE' => ('UNAVAILABLE', 'Rider location temporarily unavailable', 'Last updated ${agoText(age!)}'),
      _ => ('WAITING', 'Waiting for rider location', 'Shown once ${rider['name']} shares GPS'),
    };
  }

  Widget _statusChip(FinderColors c, (String, String, String?) s) {
    final live = s.$1 == 'LIVE';
    final color = live ? c.success : s.$1 == 'WAITING' ? c.muted : c.warn;
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: c.card,
        elevation: 3,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (live)
              Container(key: const ValueKey('live-badge'), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: c.success, borderRadius: BorderRadius.circular(4)),
                  child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)))
            else
              Icon(s.$1 == 'WAITING' ? Icons.hourglass_top : Icons.signal_wifi_statusbar_connected_no_internet_4, size: 16, color: color),
            const SizedBox(width: 8),
            Flexible(child: Text(s.$3 ?? s.$2, key: const ValueKey('track-freshness'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: c.charcoal))),
          ]),
        ),
      ),
    );
  }

  Widget _pinButton() => OutlinedButton.icon(key: const ValueKey('confirm-pin'), onPressed: _confirmPin, icon: const Icon(Icons.pin_drop_outlined), label: const Text('Confirm delivery pin'));

  Widget _details(FinderColors c, Json d) {
    final text = Theme.of(context).textTheme;
    final eta = (d['eta'] as Map?) ?? const {};
    final status = _riderStatus(d);
    final seconds = eta['seconds'] as int?;
    final arrival = DateTime.tryParse(eta['arrivalAt']?.toString() ?? '')?.toLocal();
    final schedule = d['schedule'] as Map?;
    final scheduleStatus = eta['scheduleStatus'] as String?;
    String two(int n) => n.toString().padLeft(2, '0');
    String clock(DateTime t) => '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
    final routed = eta['source'] == 'ROUTED';
    final distance = eta['distanceMeters'] as int?, straight = eta['straightLineMeters'] as int?;
    final rider = d['rider'] as Map?;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      Container(
        key: const ValueKey('eta-card'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.forest, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                d['terminal'] == true
                    ? (d['status'] == 'DELIVERED' ? 'Delivered' : 'Order ${(d['status'] as String).toLowerCase()}')
                    : seconds == null
                        ? 'Arrival time unavailable'
                        : 'Arriving in ${math.max(1, (seconds / 60).ceil())} min',
                key: const ValueKey('eta-headline'),
                style: text.headlineSmall?.copyWith(color: c.onForest, fontWeight: FontWeight.w900),
              ),
            ),
            if (seconds != null && d['terminal'] != true)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: routed ? c.gold : c.onForest.withValues(alpha: .15), borderRadius: BorderRadius.circular(999)),
                child: Text(routed ? 'Road route' : 'Estimate', key: const ValueKey('eta-source'), style: text.labelSmall?.copyWith(color: routed ? c.forest : c.onForest, fontWeight: FontWeight.w800)),
              ),
          ]),
          if (arrival != null && d['terminal'] != true) Text('Expected by ${clock(arrival)}', style: text.titleSmall?.copyWith(color: c.onForest.withValues(alpha: .9))),
          const SizedBox(height: 6),
          if (distance != null) Text('${(distance / 1000).toStringAsFixed(1)} km by road', key: const ValueKey('eta-distance'), style: text.bodyMedium?.copyWith(color: c.onForest))
          else if (straight != null) Text('About ${(straight / 1000).toStringAsFixed(1)} km away in a straight line', key: const ValueKey('eta-distance'), style: text.bodyMedium?.copyWith(color: c.onForest)),
          if (eta['basis'] != null && d['terminal'] != true) Text('Based on ${eta['basis']}', style: text.bodySmall?.copyWith(color: c.onForest.withValues(alpha: .75))),
          if (schedule != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.event_available, size: 16, color: c.gold),
              const SizedBox(width: 6),
              Expanded(child: Text('Scheduled window ${_window(schedule, clock)}', style: text.bodySmall?.copyWith(color: c.onForest))),
              if (scheduleStatus != null)
                Container(
                  key: const ValueKey('schedule-status'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: scheduleStatus == 'ON_TRACK' ? c.success : c.warn, borderRadius: BorderRadius.circular(999)),
                  child: Text(scheduleStatus == 'ON_TRACK' ? 'On track' : scheduleStatus == 'AT_RISK' ? 'At risk' : 'Delayed', style: text.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      if (rider != null)
        _tile(c, Icons.two_wheeler, '${rider['name']} · your delivery partner', status.$3 == null ? status.$2 : '${status.$2} · ${status.$3}'),
      if (d['destination'] == null && d['terminal'] != true)
        _tile(c, Icons.pin_drop_outlined, 'Delivery pin not confirmed', d['destinationNote'] as String? ?? '', trailing: _pinButton()),
      if ((d['restaurant'] as Map?)?['location'] == null && d['terminal'] != true)
        _tile(c, Icons.storefront, d['restaurant']?['name'] as String? ?? 'Restaurant', 'Pickup point not configured yet, so it is not shown on the map'),
      _tile(c, connection.contains('connected') ? Icons.wifi : Icons.wifi_off, 'Connection', connection),
      const SizedBox(height: 8),
      _timeline(c, d['status'] as String),
    ]);
  }

  String _window(Map schedule, String Function(DateTime) clock) {
    final a = DateTime.tryParse(schedule['windowStart']?.toString() ?? '')?.toLocal(), b = DateTime.tryParse(schedule['windowEnd']?.toString() ?? '')?.toLocal();
    return a == null || b == null ? '' : '${clock(a)} – ${clock(b)}';
  }

  Widget _tile(FinderColors c, IconData icon, String title, String subtitle, {Widget? trailing}) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(backgroundColor: c.paleGreen, child: Icon(icon, color: c.forest)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(color: c.muted)),
              if (trailing != null) Padding(padding: const EdgeInsets.only(top: 6), child: trailing),
            ])),
          ]),
        ),
      );

  Widget _timeline(FinderColors c, String status) {
    const steps = [('ACCEPTED', 'Order accepted'), ('PREPARING', 'Preparing your food'), ('READY_FOR_PICKUP', 'Ready for pickup'), ('PICKED_UP', 'Picked up'), ('OUT_FOR_DELIVERY', 'On the way'), ('DELIVERED', 'Delivered')];
    const order = ['PENDING_RESTAURANT', 'ACCEPTED', 'PREPARING', 'READY_FOR_PICKUP', 'PICKED_UP', 'OUT_FOR_DELIVERY', 'DELIVERED'];
    final reached = order.indexOf(status);
    return Card(
      key: const ValueKey('track-timeline'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Delivery timeline', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final (key, label) in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(order.indexOf(key) <= reached ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: order.indexOf(key) <= reached ? c.success : c.outline),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: order.indexOf(key) == reached ? FontWeight.w800 : FontWeight.w500)),
              ]),
            ),
        ]),
      ),
    );
  }
}
