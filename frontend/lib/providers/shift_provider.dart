import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/voiceops_api.dart';

/// The driver's active shift id, or null before one is started. The voice
/// socket lives at `/ws/voice/{shift_id}`, so the voice session starts a
/// shift (`POST /v1/shift/start`) the first time the driver talks.
final shiftProvider = StateNotifierProvider<ShiftNotifier, String?>(
  (ref) => ShiftNotifier(ref.watch(voiceOpsApiProvider)),
);

class ShiftNotifier extends StateNotifier<String?> {
  ShiftNotifier(this._api) : super(null);

  final VoiceOpsApi _api;
  Future<String>? _starting;

  /// The active shift id, starting a shift if there is none. Concurrent
  /// callers share one request; a failure lets the next call try again.
  Future<String> ensureStarted() async {
    if (state case final id?) return id;
    final starting = _starting ??= _api.startShift();
    try {
      final id = await starting;
      if (mounted) state = id;
      return id;
    } finally {
      _starting = null;
    }
  }

  /// Forget the shift (e.g. on sign-out).
  void clear() => state = null;
}
