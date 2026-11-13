import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);
final apiClientProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://10.0.2.2:5000/api/v1/',
      ),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  ),
);
final appearanceProvider = NotifierProvider<Appearance, ThemeMode>(
  Appearance.new,
);

class Appearance extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    try {
      final value = ref.read(preferencesProvider).getString('appearance');
      return ThemeMode.values.where((m) => m.name == value).firstOrNull ??
          ThemeMode.system;
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<bool> select(ThemeMode mode) async {
    try {
      final saved = await ref
          .read(preferencesProvider)
          .setString('appearance', mode.name);
      if (saved) state = mode;
      return saved;
    } catch (_) {
      return false;
    }
  }
}

class ServiceArea {
  final String id, name, city;
  const ServiceArea(this.id, this.name, [this.city = 'Hyderabad']);

  static const defaultArea = ServiceArea('madhapur', 'Madhapur');

  static const hyderabadAreas = [
    ServiceArea('gachibowli', 'Gachibowli'),
    ServiceArea('madhapur', 'Madhapur'),
    ServiceArea('hitec-city', 'HITEC City'),
    ServiceArea('kondapur', 'Kondapur'),
    ServiceArea('kukatpally', 'Kukatpally / KPHB'),
    ServiceArea('jubilee-hills', 'Jubilee Hills'),
    ServiceArea('banjara-hills', 'Banjara Hills'),
    ServiceArea('ameerpet', 'Ameerpet'),
    ServiceArea('mehdipatnam', 'Mehdipatnam'),
    ServiceArea('secunderabad', 'Secunderabad'),
  ];

  factory ServiceArea.fromJson(Map<String, dynamic> json) => ServiceArea(
    json['id'] as String,
    json['name'] as String,
    (json['city'] as String?) ?? 'Hyderabad',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ServiceArea && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

final locationProvider = NotifierProvider<Location, ServiceArea>(Location.new);

class Location extends Notifier<ServiceArea> {
  @override
  ServiceArea build() {
    final saved = ref.read(preferencesProvider).getString('locality');
    return ServiceArea.hyderabadAreas.where((a) => a.id == saved).firstOrNull ??
        ServiceArea.defaultArea;
  }

  Future<void> select(ServiceArea area) async {
    state = area;
    try {
      await ref.read(preferencesProvider).setString('locality', area.id);
    } catch (_) {
      // Keep the selected locality in memory if preferences storage fails.
    }
  }
}
