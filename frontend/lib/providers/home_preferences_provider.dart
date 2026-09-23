import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional detail sections on the Home screen. The detail sections are
/// deliberately off until the driver chooses a denser Home layout in
/// Settings. The Next Orders card and the target indicator are the
/// exception: they are on by default and the driver can hide them.
class HomePreferences {
  const HomePreferences({
    this.quickActionsEnabled = false,
    this.conversationEnabled = false,
    this.locationEnabled = false,
    this.nextOrdersEnabled = true,
    this.targetEnabled = true,
  });

  final bool quickActionsEnabled;
  final bool conversationEnabled;
  final bool locationEnabled;
  final bool nextOrdersEnabled;
  final bool targetEnabled;

  HomePreferences copyWith({
    bool? quickActionsEnabled,
    bool? conversationEnabled,
    bool? locationEnabled,
    bool? nextOrdersEnabled,
    bool? targetEnabled,
  }) => HomePreferences(
    quickActionsEnabled: quickActionsEnabled ?? this.quickActionsEnabled,
    conversationEnabled: conversationEnabled ?? this.conversationEnabled,
    locationEnabled: locationEnabled ?? this.locationEnabled,
    nextOrdersEnabled: nextOrdersEnabled ?? this.nextOrdersEnabled,
    targetEnabled: targetEnabled ?? this.targetEnabled,
  );
}

abstract interface class HomePreferencesStore {
  Future<HomePreferences> load();
  Future<void> saveQuickActions({required bool enabled});
  Future<void> saveConversation({required bool enabled});
  Future<void> saveLocation({required bool enabled});
  Future<void> saveNextOrders({required bool enabled});
  Future<void> saveTarget({required bool enabled});
}

class SharedPreferencesHomePreferencesStore implements HomePreferencesStore {
  const SharedPreferencesHomePreferencesStore();

  static const _quickActionsKey = 'home_quick_actions';
  static const _conversationKey = 'home_conversation';
  static const _locationKey = 'home_location';
  static const _nextOrdersKey = 'home_next_orders';
  static const _targetKey = 'home_target';

  @override
  Future<HomePreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    return HomePreferences(
      quickActionsEnabled: preferences.getBool(_quickActionsKey) ?? false,
      conversationEnabled: preferences.getBool(_conversationKey) ?? false,
      locationEnabled: preferences.getBool(_locationKey) ?? false,
      nextOrdersEnabled: preferences.getBool(_nextOrdersKey) ?? true,
      targetEnabled: preferences.getBool(_targetKey) ?? true,
    );
  }

  @override
  Future<void> saveQuickActions({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(
      _quickActionsKey,
      enabled,
    );
  }

  @override
  Future<void> saveConversation({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(
      _conversationKey,
      enabled,
    );
  }

  @override
  Future<void> saveLocation({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(
      _locationKey,
      enabled,
    );
  }

  @override
  Future<void> saveNextOrders({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(
      _nextOrdersKey,
      enabled,
    );
  }

  @override
  Future<void> saveTarget({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(_targetKey, enabled);
  }
}

final homePreferencesStoreProvider = Provider<HomePreferencesStore>(
  (ref) => const SharedPreferencesHomePreferencesStore(),
);

final homePreferencesProvider =
    StateNotifierProvider<HomePreferencesController, HomePreferences>(
      HomePreferencesController.new,
    );

class HomePreferencesController extends StateNotifier<HomePreferences> {
  HomePreferencesController(this._ref) : super(const HomePreferences()) {
    unawaited(_loadSaved());
  }

  final Ref _ref;
  bool _quickActionsChangedLocally = false;
  bool _conversationChangedLocally = false;
  bool _locationChangedLocally = false;
  bool _nextOrdersChangedLocally = false;
  bool _targetChangedLocally = false;

  Future<void> _loadSaved() async {
    try {
      final saved = await _ref.read(homePreferencesStoreProvider).load();
      if (!mounted) return;
      state = HomePreferences(
        quickActionsEnabled: _quickActionsChangedLocally
            ? state.quickActionsEnabled
            : saved.quickActionsEnabled,
        conversationEnabled: _conversationChangedLocally
            ? state.conversationEnabled
            : saved.conversationEnabled,
        locationEnabled: _locationChangedLocally
            ? state.locationEnabled
            : saved.locationEnabled,
        nextOrdersEnabled: _nextOrdersChangedLocally
            ? state.nextOrdersEnabled
            : saved.nextOrdersEnabled,
        targetEnabled: _targetChangedLocally
            ? state.targetEnabled
            : saved.targetEnabled,
      );
    } catch (_) {
      // Unreadable or absent preferences keep the defaults: detail sections hidden,
      // the Next Orders card and target indicator shown.
    }
  }

  void setQuickActions({required bool enabled}) {
    _quickActionsChangedLocally = true;
    state = state.copyWith(quickActionsEnabled: enabled);
    unawaited(
      _save(
        () => _ref
            .read(homePreferencesStoreProvider)
            .saveQuickActions(enabled: enabled),
      ),
    );
  }

  void setConversation({required bool enabled}) {
    _conversationChangedLocally = true;
    state = state.copyWith(conversationEnabled: enabled);
    unawaited(
      _save(
        () => _ref
            .read(homePreferencesStoreProvider)
            .saveConversation(enabled: enabled),
      ),
    );
  }

  void setLocation({required bool enabled}) {
    _locationChangedLocally = true;
    state = state.copyWith(locationEnabled: enabled);
    unawaited(
      _save(
        () => _ref
            .read(homePreferencesStoreProvider)
            .saveLocation(enabled: enabled),
      ),
    );
  }

  void setNextOrders({required bool enabled}) {
    _nextOrdersChangedLocally = true;
    state = state.copyWith(nextOrdersEnabled: enabled);
    unawaited(
      _save(
        () => _ref
            .read(homePreferencesStoreProvider)
            .saveNextOrders(enabled: enabled),
      ),
    );
  }

  void setTarget({required bool enabled}) {
    _targetChangedLocally = true;
    state = state.copyWith(targetEnabled: enabled);
    unawaited(
      _save(
        () => _ref
            .read(homePreferencesStoreProvider)
            .saveTarget(enabled: enabled),
      ),
    );
  }

  Future<void> _save(Future<void> Function() save) async {
    try {
      await save();
    } catch (_) {
      // Keep the immediate in-memory choice. A later change retries saving.
    }
  }
}
