import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The four push-to-talk states (frontend rules). Never collapse them.
enum PushToTalkState { idle, recording, processing, speaking }

/// What the push-to-talk button shows. The voice session
/// (`voiceSessionProvider`, the single WebSocket owner) drives it: the mic
/// streaming is `recording`, waiting on the co-rider is `processing`, its
/// reply playing is `speaking`.
final pushToTalkProvider =
    StateNotifierProvider<PushToTalkNotifier, PushToTalkState>((ref) {
      return PushToTalkNotifier();
    });

class PushToTalkNotifier extends StateNotifier<PushToTalkState> {
  PushToTalkNotifier() : super(PushToTalkState.idle);

  void set(PushToTalkState next) => state = next;
}

/// True while the mic streams during a continuous conversation.
final micLiveProvider = StateProvider<bool>((ref) => false);
