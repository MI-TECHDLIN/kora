import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/voiceops_api.dart';

/// A geographic area the driver drew for auto-accept, matching the backend's
/// `GeoZone` (`app/services/preference_models.py`) stored under the
/// `geographic_zones` preference key.
class AutoAcceptZone {
  const AutoAcceptZone({
    required this.name,
    required this.avoided,
    required this.radiusKm,
    this.centerLat,
    this.centerLng,
  });

  final String name;

  /// false = a preferred area (help it clear), true = an avoided one.
  final bool avoided;
  final double radiusKm;
  final double? centerLat;
  final double? centerLng;

  factory AutoAcceptZone.fromJson(Map<String, dynamic> json) => AutoAcceptZone(
    name: json['name'] as String? ?? '',
    avoided: json['zone_type'] == 'avoided',
    radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 0,
    centerLat: (json['center_lat'] as num?)?.toDouble(),
    centerLng: (json['center_lng'] as num?)?.toDouble(),
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'center_lat': centerLat ?? 0.0,
    'center_lng': centerLng ?? 0.0,
    'radius_km': radiusKm,
    'zone_type': avoided ? 'avoided' : 'preferred',
  };
}

/// Everything the driver has set for auto-accept, by voice or this Settings
/// screen — the same `driver_preferences` rows either surface reads/writes.
class AutoAcceptPreferences {
  const AutoAcceptPreferences({
    this.enabled = false,
    this.maxDistanceKm,
    this.zones = const [],
    this.acceptedCategories = const [],
  });

  /// Off by default: nothing auto-accepts until the driver opts in.
  final bool enabled;
  final double? maxDistanceKm;
  final List<AutoAcceptZone> zones;
  final List<String> acceptedCategories;

  AutoAcceptPreferences copyWith({
    bool? enabled,
    double? maxDistanceKm,
    bool clearMaxDistanceKm = false,
    List<AutoAcceptZone>? zones,
    List<String>? acceptedCategories,
  }) => AutoAcceptPreferences(
    enabled: enabled ?? this.enabled,
    maxDistanceKm: clearMaxDistanceKm
        ? null
        : (maxDistanceKm ?? this.maxDistanceKm),
    zones: zones ?? this.zones,
    acceptedCategories: acceptedCategories ?? this.acceptedCategories,
  );
}

final autoAcceptPreferencesProvider =
    StateNotifierProvider<
      AutoAcceptPreferencesController,
      AutoAcceptPreferences
    >(AutoAcceptPreferencesController.new);

/// Reads and writes the backend's `auto_accept_orders`, `max_order_distance_km`,
/// `geographic_zones` and `order_type_prefs` keys — the same keys
/// `app/agents/tools/preferences.py` writes when the driver says it out loud,
/// so this screen and voice always agree on one state.
class AutoAcceptPreferencesController
    extends StateNotifier<AutoAcceptPreferences> {
  AutoAcceptPreferencesController(this._ref)
    : super(const AutoAcceptPreferences()) {
    unawaited(reload());
  }

  final Ref _ref;

  Future<void> reload() async {
    try {
      final raw = await _ref.read(koraApiProvider).fetchDriverPreferences();
      if (!mounted) return;
      state = AutoAcceptPreferences(
        enabled: raw['auto_accept_orders'] == 'true',
        maxDistanceKm: double.tryParse(raw['max_order_distance_km'] ?? ''),
        zones: _parseZones(raw['geographic_zones']),
        acceptedCategories: _parseCategories(raw['order_type_prefs']),
      );
    } catch (_) {
      // Stay off (the safe default) until the next reload succeeds.
    }
  }

  static List<AutoAcceptZone> _parseZones(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((zone) => AutoAcceptZone.fromJson(zone as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<String> _parseCategories(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final categories = (jsonDecode(raw) as Map<String, dynamic>)['accepted_categories'];
      if (categories is List) return categories.map((c) => c.toString()).toList();
    } catch (_) {
      // Falls through to no restriction.
    }
    return const [];
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      await _ref
          .read(koraApiProvider)
          .setDriverPreference(
            'auto_accept_orders',
            enabled ? 'true' : 'false',
          );
      if (!mounted) return;
      state = state.copyWith(enabled: enabled);
    } catch (_) {
      // Keep showing the last value loaded from the backend when the write fails.
    }
  }

  Future<void> setMaxDistanceKm(double? km) async {
    state = state.copyWith(maxDistanceKm: km, clearMaxDistanceKm: km == null);
    if (km == null) {
      await _clear('max_order_distance_km');
    } else {
      await _write('max_order_distance_km', km.toString());
    }
  }

  Future<void> addZone(AutoAcceptZone zone) async {
    final zones = [
      ...state.zones.where((existing) => existing.name != zone.name),
      zone,
    ];
    state = state.copyWith(zones: zones);
    await _writeZones(zones);
  }

  Future<void> removeZone(String name) async {
    final zones = state.zones.where((zone) => zone.name != name).toList();
    state = state.copyWith(zones: zones);
    await _writeZones(zones);
  }

  Future<void> _writeZones(List<AutoAcceptZone> zones) => zones.isEmpty
      ? _clear('geographic_zones')
      : _write(
          'geographic_zones',
          jsonEncode(zones.map((zone) => zone.toJson()).toList()),
        );

  Future<void> addCategory(String category) async {
    final trimmed = category.trim();
    if (trimmed.isEmpty || state.acceptedCategories.contains(trimmed)) return;
    final categories = [...state.acceptedCategories, trimmed];
    state = state.copyWith(acceptedCategories: categories);
    await _writeCategories(categories);
  }

  Future<void> removeCategory(String category) async {
    final categories = state.acceptedCategories
        .where((existing) => existing != category)
        .toList();
    state = state.copyWith(acceptedCategories: categories);
    await _writeCategories(categories);
  }

  Future<void> _writeCategories(List<String> categories) => categories.isEmpty
      ? _clear('order_type_prefs')
      : _write(
          'order_type_prefs',
          jsonEncode({'accepted_categories': categories}),
        );

  Future<void> _write(String key, String value) async {
    try {
      await _ref.read(koraApiProvider).setDriverPreference(key, value);
    } catch (_) {
      // Keep the in-memory choice; the next reload reconciles with the backend.
    }
  }

  Future<void> _clear(String key) async {
    try {
      await _ref.read(koraApiProvider).clearDriverPreference(key);
    } catch (_) {
      // Keep the in-memory choice; the next reload reconciles with the backend.
    }
  }
}
