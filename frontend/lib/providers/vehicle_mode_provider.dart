import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../core/api/voiceops_api.dart';
import 'driver_details_provider.dart';

/// The map marker the driver prefers. A motorbike and a pedal bicycle are
/// deliberately separate because Kora serves both kinds of rider.
enum VehicleMode {
  car('Car', TablerIcons.carFilled),
  motorbike('Motorbike', TablerIcons.motorbikeFilled),
  bicycle('Bicycle', TablerIcons.bikeFilled);

  const VehicleMode(this.label, this.icon);

  final String label;
  final IconData icon;

  static VehicleMode fromProfile(String? value) {
    final type = value?.toLowerCase() ?? '';
    if (type.contains('motor') ||
        type.contains('scooter') ||
        type.contains('okada')) {
      return motorbike;
    }
    if (type.contains('bike') || type.contains('cycle')) return bicycle;
    return car;
  }
}

abstract interface class VehicleModeStore {
  Future<VehicleMode?> load();
  Future<void> save(VehicleMode mode);
}

class SharedPreferencesVehicleModeStore implements VehicleModeStore {
  const SharedPreferencesVehicleModeStore();

  static const _key = 'map_vehicle_mode';

  @override
  Future<VehicleMode?> load() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return VehicleMode.values.where((mode) => mode.name == value).firstOrNull;
  }

  @override
  Future<void> save(VehicleMode mode) async {
    await (await SharedPreferences.getInstance()).setString(_key, mode.name);
  }
}

final vehicleModeStoreProvider = Provider<VehicleModeStore>(
  (ref) => const SharedPreferencesVehicleModeStore(),
);

final vehicleModeProvider =
    StateNotifierProvider<VehicleModeController, VehicleMode>(
      VehicleModeController.new,
    );

class VehicleModeController extends StateNotifier<VehicleMode> {
  VehicleModeController(this._ref) : super(VehicleMode.car) {
    _ref.listen<AsyncValue<DriverProfile>>(driverDetailsProvider, (_, profile) {
      final driver = profile.valueOrNull;
      if (driver != null && !_selectedLocally && !_hasSavedMode) {
        state = VehicleMode.fromProfile(driver.vehicleType);
      }
    }, fireImmediately: true);
    unawaited(_loadSavedMode());
  }

  final Ref _ref;
  bool _selectedLocally = false;
  bool _hasSavedMode = false;

  Future<void> _loadSavedMode() async {
    try {
      final saved = await _ref.read(vehicleModeStoreProvider).load();
      if (_selectedLocally) return;
      if (saved != null) {
        _hasSavedMode = true;
        state = saved;
      }
    } catch (_) {
      // A missing local preference leaves the backend profile (or safe car
      // default) in charge. The profile card owns its error and retry state.
    }
  }

  void select(VehicleMode mode) {
    _selectedLocally = true;
    _hasSavedMode = true;
    state = mode;
    unawaited(_save(mode));
  }

  Future<void> _save(VehicleMode mode) async {
    try {
      await _ref.read(vehicleModeStoreProvider).save(mode);
    } catch (_) {
      // Keep the selection for this run. A later choice retries persistence.
    }
  }
}
