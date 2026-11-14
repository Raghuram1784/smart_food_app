import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'customer_location_service.dart';

enum PickedLocationSource { deviceGps, customerMapPin }

extension PickedLocationSourceApi on PickedLocationSource {
  String get api => this == PickedLocationSource.deviceGps ? 'DEVICE_GPS' : 'CUSTOMER_MAP_PIN';
}

/// A delivery point the customer explicitly confirmed on the map.
class PickedLocation {
  final double latitude;
  final double longitude;
  final PickedLocationSource source;

  /// GPS accuracy; only meaningful when the pin is exactly the device fix.
  final double? accuracyMeters;
  const PickedLocation({
    required this.latitude,
    required this.longitude,
    required this.source,
    this.accuracyMeters,
  });
}

/// Returned when the customer prefers typing the address without a map point.
class ManualAddressChoice {
  const ManualAddressChoice();
}

/// Map picker for a delivery destination.
///
/// The map is only shown once a real starting point exists (a fresh device fix
/// or the address's previously confirmed point). There is no default city.
class LocationPickerScreen extends ConsumerStatefulWidget {
  /// Previously confirmed point to start from (editing an address).
  final LatLng? initialPoint;

  /// Fetch a device fix on open (Use current location).
  final bool startWithGps;
  const LocationPickerScreen({super.key, this.initialPoint, this.startWithGps = true});

  @override
  ConsumerState<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  DeviceFix? _fix;
  LatLng? _pin;
  LatLng? _start;
  LocationFailure? _failure;
  bool _locating = false;

  // MapController may only be used after onMapReady; using it earlier throws
  // during build (see RiderMapWidget regression). Created once, disposed here.
  MapController? _controller;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPoint != null) {
      _start = widget.initialPoint;
      _pin = widget.initialPoint;
    }
    if (widget.startWithGps || widget.initialPoint == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _failure = null;
    });
    try {
      final fix = await ref.read(customerLocationServiceProvider).currentFix();
      if (!mounted) return;
      final point = LatLng(fix.latitude, fix.longitude);
      setState(() {
        _fix = fix;
        _start ??= point;
        // Only move the pin to GPS if the customer hasn't placed one yet.
        _pin ??= point;
      });
      _moveCamera(point);
    } on LocationFailure catch (f) {
      if (mounted) setState(() => _failure = f);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onMapReady() => _mapReady = true;

  void _moveCamera(LatLng to) {
    final c = _controller;
    if (!_mapReady || c == null) return;
    c.move(to, c.camera.zoom < 15 ? 16 : c.camera.zoom);
  }

  void _zoomBy(double d) {
    final c = _controller;
    if (!_mapReady || c == null) return;
    c.move(c.camera.center, (c.camera.zoom + d).clamp(3.0, 19.0));
  }

  void _pinToCenter() {
    final c = _controller;
    if (!_mapReady || c == null) return;
    setState(() => _pin = c.camera.center);
  }

  bool get _pinIsGpsFix =>
      _fix != null && _pin != null && _pin!.latitude == _fix!.latitude && _pin!.longitude == _fix!.longitude;

  void _confirm() {
    final pin = _pin;
    if (pin == null) return;
    Navigator.of(context).pop(PickedLocation(
      latitude: double.parse(pin.latitude.toStringAsFixed(6)),
      longitude: double.parse(pin.longitude.toStringAsFixed(6)),
      source: _pinIsGpsFix ? PickedLocationSource.deviceGps : PickedLocationSource.customerMapPin,
      accuracyMeters: _pinIsGpsFix ? _fix!.accuracyMeters : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set delivery location'),
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _start == null ? _noStartingPoint(theme) : _map(theme, scheme),
    );
  }

  Widget _noStartingPoint(ThemeData theme) {
    final f = _failure;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_locating || f == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Getting your current location…', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('Using this device\'s GPS', style: theme.textTheme.bodySmall),
            ] else ...[
              Icon(Icons.location_disabled_outlined, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text('Location unavailable', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(f.message, textAlign: TextAlign.center, key: const ValueKey('location-failure')),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.tonal(onPressed: _locate, child: const Text('Retry')),
                  if (f.needsLocationSettings)
                    OutlinedButton(
                      onPressed: () => ref.read(locationPlatformProvider).openLocationSettings(),
                      child: const Text('Location settings'),
                    ),
                  if (f.needsAppSettings || f.kind == LocationFailureKind.permissionDenied)
                    OutlinedButton(
                      onPressed: () => ref.read(locationPlatformProvider).openAppSettings(),
                      child: const Text('App settings'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(const ManualAddressChoice()),
                    child: const Text('Enter address manually'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _map(ThemeData theme, ColorScheme scheme) {
    final controller = _controller ??= MapController();
    final fix = _fix;
    final fixPoint = fix == null ? null : LatLng(fix.latitude, fix.longitude);
    final pin = _pin!;
    final distance = fixPoint == null
        ? null
        : Geolocator.distanceBetween(fixPoint.latitude, fixPoint.longitude, pin.latitude, pin.longitude);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: _start!,
                  initialZoom: 16.5,
                  minZoom: 3,
                  maxZoom: 19,
                  onMapReady: _onMapReady,
                  onTap: (_, point) => setState(() => _pin = point),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.smartfood.app',
                  ),
                  if (fixPoint != null)
                    CircleLayer(circles: [
                      CircleMarker(
                        point: fixPoint,
                        radius: fix!.accuracyMeters.clamp(5.0, 500.0),
                        useRadiusInMeter: true,
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderColor: Colors.blue.withValues(alpha: 0.5),
                        borderStrokeWidth: 1,
                      ),
                    ]),
                  MarkerLayer(markers: [
                    if (fixPoint != null)
                      Marker(
                        point: fixPoint,
                        width: 18,
                        height: 18,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    Marker(
                      point: pin,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on, size: 44, color: scheme.primary, key: const ValueKey('destination-pin')),
                    ),
                  ]),
                  const SimpleAttributionWidget(source: Text('© OpenStreetMap contributors')),
                ],
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(12),
                  color: scheme.surface.withValues(alpha: 0.95),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Tap the map to set the exact delivery point',
                            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          fix != null
                              ? 'Your GPS: ±${fix.accuracyMeters.round()} m'
                                  '${distance != null && distance > 1 ? ' · pin is ${_fmt(distance)} from you (straight line)' : ' · pin is at your current position'}'
                              : _locating
                                  ? 'Getting your current location…'
                                  : 'Current location not available — editing the saved pin',
                          style: theme.textTheme.bodySmall,
                          key: const ValueKey('picker-gps-status'),
                        ),
                        if (_failure != null && fix == null)
                          Text(_failure!.message, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoundButton(
                      icon: Icons.my_location,
                      tooltip: 'Recenter on my location',
                      onPressed: _locating
                          ? null
                          : () {
                              if (fixPoint != null) {
                                _moveCamera(fixPoint);
                              } else {
                                _locate();
                              }
                            },
                    ),
                    const SizedBox(height: 6),
                    _RoundButton(icon: Icons.add, tooltip: 'Zoom in', onPressed: () => _zoomBy(1)),
                    const SizedBox(height: 4),
                    _RoundButton(icon: Icons.remove, tooltip: 'Zoom out', onPressed: () => _zoomBy(-1)),
                    const SizedBox(height: 6),
                    _RoundButton(icon: Icons.center_focus_strong, tooltip: 'Move pin to map centre', onPressed: _pinToCenter),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm location'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _fmt(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const _RoundButton({required this.icon, required this.tooltip, this.onPressed});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.95),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
      ),
    );
  }
}
