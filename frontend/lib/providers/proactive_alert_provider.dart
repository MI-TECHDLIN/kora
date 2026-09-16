import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime/voice_events.dart';
import '../core/theme/tokens.dart';

/// The proactive alert the driver is being shown right now, or null. The
/// co-rider also says it out loud, but audio can be missed at 50 km/h with
/// the window down, so it is always shown as well.
///
/// One at a time on purpose: a newer risk replaces an older one rather than
/// stacking notices over the map.
final proactiveAlertProvider =
    StateNotifierProvider<ProactiveAlertNotifier, ProactiveAlertEvent?>(
      (ref) => ProactiveAlertNotifier(),
    );

class ProactiveAlertNotifier extends StateNotifier<ProactiveAlertEvent?> {
  ProactiveAlertNotifier() : super(null);

  Timer? _timer;

  void show(ProactiveAlertEvent alert) {
    _timer?.cancel();
    state = alert;
    _timer = Timer(VoiceOpsMotion.proactiveAlert, dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (state != null) state = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
