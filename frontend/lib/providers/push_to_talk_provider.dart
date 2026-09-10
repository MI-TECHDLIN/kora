import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The four push-to-talk states (frontend rules). Never collapse them.
enum PushToTalkState { idle, recording, processing, speaking }

/// Placeholder. The voice-session provider — the single WebSocket owner —
/// will drive this once audio and the socket land. Until then the button
/// can cycle states for design review. No audio capture happens here.
final pushToTalkProvider =
    StateNotifierProvider<PushToTalkNotifier, PushToTalkState>((ref) {
      return PushToTalkNotifier();
    });

class PushToTalkNotifier extends StateNotifier<PushToTalkState> {
  PushToTalkNotifier() : super(PushToTalkState.idle);

  void set(PushToTalkState next) => state = next;

  /// Demo cycle: idle → recording → processing → speaking → idle.
  void advance() => state =
      PushToTalkState.values[(state.index + 1) % PushToTalkState.values.length];
}
