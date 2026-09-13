import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime/voice_events.dart';

/// The customer call in progress, or null. Opened by `call_started`, closed
/// by `call_ended` (docs/contracts/interface.md §1). The call overlay reads
/// it; the driver ends a call through the voice session.
final activeCallProvider =
    StateNotifierProvider<ActiveCallNotifier, CallStartedEvent?>(
      (ref) => ActiveCallNotifier(),
    );

class ActiveCallNotifier extends StateNotifier<CallStartedEvent?> {
  ActiveCallNotifier() : super(null);

  void start(CallStartedEvent call) => state = call;

  /// Closes [callId] if it is the call shown; a stale id is ignored.
  void end(String callId) {
    if (state?.callId == callId) state = null;
  }
}
