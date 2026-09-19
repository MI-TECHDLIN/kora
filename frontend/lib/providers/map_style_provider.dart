import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../core/theme/tokens.dart';

/// The OpenFreeMap style the driver picked in Settings. Separate from the app
/// theme (always dark): a light map can read better in bright daylight.
enum MapStyle {
  dark('Dark', TablerIcons.moon, 'dark', KoraColors.mapGroundDark),
  light('Light', TablerIcons.sun, 'positron', KoraColors.mapGroundLight),
  detailed(
    'Detailed',
    TablerIcons.buildingCommunity,
    'liberty',
    KoraColors.mapGroundDetailed,
  );

  const MapStyle(this.label, this.icon, this.openFreeMapName, this.ground);

  final String label;
  final IconData icon;

  /// The style's name at https://tiles.openfreemap.org/styles/.
  final String openFreeMapName;

  /// The style's background colour, painted under its tiles.
  final Color ground;

  String get url => 'https://tiles.openfreemap.org/styles/$openFreeMapName';

  bool get isDark => this == dark;
}

abstract interface class MapStyleStore {
  Future<MapStyle?> load();
  Future<void> save(MapStyle style);
}

class SharedPreferencesMapStyleStore implements MapStyleStore {
  const SharedPreferencesMapStyleStore();

  static const _key = 'map_style';

  @override
  Future<MapStyle?> load() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return MapStyle.values.where((style) => style.name == value).firstOrNull;
  }

  @override
  Future<void> save(MapStyle style) async {
    await (await SharedPreferences.getInstance()).setString(_key, style.name);
  }
}

final mapStyleStoreProvider = Provider<MapStyleStore>(
  (ref) => const SharedPreferencesMapStyleStore(),
);

final mapStyleProvider = StateNotifierProvider<MapStyleController, MapStyle>(
  MapStyleController.new,
);

/// Dark by default, matching the dark-mode-first app, until the saved choice
/// loads.
class MapStyleController extends StateNotifier<MapStyle> {
  MapStyleController(this._ref) : super(MapStyle.dark) {
    unawaited(_loadSaved());
  }

  final Ref _ref;
  bool _selectedLocally = false;

  Future<void> _loadSaved() async {
    try {
      final saved = await _ref.read(mapStyleStoreProvider).load();
      if (!_selectedLocally && saved != null && mounted) state = saved;
    } catch (_) {
      // No readable preference: keep the dark default.
    }
  }

  void select(MapStyle style) {
    _selectedLocally = true;
    state = style;
    unawaited(_save(style));
  }

  Future<void> _save(MapStyle style) async {
    try {
      await _ref.read(mapStyleStoreProvider).save(style);
    } catch (_) {
      // Keep the choice for this run. A later choice retries persistence.
    }
  }
}
