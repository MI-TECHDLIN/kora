import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The client-side reactions the driver can silence. Events still arrive and
/// durable data, such as a completed shift summary, is still retained.
class NotificationPreferences {
  const NotificationPreferences({
    this.proactiveAlertsEnabled = true,
    this.shiftSummaryReadyEnabled = true,
  });

  final bool proactiveAlertsEnabled;
  final bool shiftSummaryReadyEnabled;

  NotificationPreferences copyWith({
    bool? proactiveAlertsEnabled,
    bool? shiftSummaryReadyEnabled,
  }) => NotificationPreferences(
    proactiveAlertsEnabled:
        proactiveAlertsEnabled ?? this.proactiveAlertsEnabled,
    shiftSummaryReadyEnabled:
        shiftSummaryReadyEnabled ?? this.shiftSummaryReadyEnabled,
  );
}

abstract interface class NotificationPreferencesStore {
  Future<NotificationPreferences> load();
  Future<void> saveProactiveAlerts({required bool enabled});
  Future<void> saveShiftSummaryReady({required bool enabled});
}

class SharedPreferencesNotificationPreferencesStore
    implements NotificationPreferencesStore {
  const SharedPreferencesNotificationPreferencesStore();

  static const _proactiveAlertsKey = 'notifications_proactive_alerts';
  static const _shiftSummaryReadyKey = 'notifications_shift_summary_ready';

  @override
  Future<NotificationPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    return NotificationPreferences(
      proactiveAlertsEnabled: preferences.getBool(_proactiveAlertsKey) ?? true,
      shiftSummaryReadyEnabled:
          preferences.getBool(_shiftSummaryReadyKey) ?? true,
    );
  }

  @override
  Future<void> saveProactiveAlerts({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(
      _proactiveAlertsKey,
      enabled,
    );
  }

  @override
  Future<void> saveShiftSummaryReady({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(
      _shiftSummaryReadyKey,
      enabled,
    );
  }
}

final notificationPreferencesStoreProvider =
    Provider<NotificationPreferencesStore>(
      (ref) => const SharedPreferencesNotificationPreferencesStore(),
    );

final notificationPreferencesProvider =
    StateNotifierProvider<
      NotificationPreferencesController,
      NotificationPreferences
    >(NotificationPreferencesController.new);

/// Both reactions are on by default, preserving the existing experience until
/// a saved choice loads.
class NotificationPreferencesController
    extends StateNotifier<NotificationPreferences> {
  NotificationPreferencesController(this._ref)
    : super(const NotificationPreferences()) {
    unawaited(_loadSaved());
  }

  final Ref _ref;
  bool _proactiveAlertsChangedLocally = false;
  bool _shiftSummaryReadyChangedLocally = false;

  Future<void> _loadSaved() async {
    try {
      final saved = await _ref
          .read(notificationPreferencesStoreProvider)
          .load();
      if (!mounted) return;
      state = NotificationPreferences(
        proactiveAlertsEnabled: _proactiveAlertsChangedLocally
            ? state.proactiveAlertsEnabled
            : saved.proactiveAlertsEnabled,
        shiftSummaryReadyEnabled: _shiftSummaryReadyChangedLocally
            ? state.shiftSummaryReadyEnabled
            : saved.shiftSummaryReadyEnabled,
      );
    } catch (_) {
      // Unreadable preferences leave both notifications on by default.
    }
  }

  void setProactiveAlerts({required bool enabled}) {
    _proactiveAlertsChangedLocally = true;
    state = state.copyWith(proactiveAlertsEnabled: enabled);
    unawaited(_saveProactiveAlerts(enabled));
  }

  void setShiftSummaryReady({required bool enabled}) {
    _shiftSummaryReadyChangedLocally = true;
    state = state.copyWith(shiftSummaryReadyEnabled: enabled);
    unawaited(_saveShiftSummaryReady(enabled));
  }

  Future<void> _saveProactiveAlerts(bool enabled) async {
    try {
      await _ref
          .read(notificationPreferencesStoreProvider)
          .saveProactiveAlerts(enabled: enabled);
    } catch (_) {
      // Keep the in-memory choice. A later change retries persistence.
    }
  }

  Future<void> _saveShiftSummaryReady(bool enabled) async {
    try {
      await _ref
          .read(notificationPreferencesStoreProvider)
          .saveShiftSummaryReady(enabled: enabled);
    } catch (_) {
      // Keep the in-memory choice. A later change retries persistence.
    }
  }
}
