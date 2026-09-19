import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'co_rider_voice_provider.dart';
import 'voice_session_provider.dart';

/// Commits [voice] as the co-rider's voice: saves it (state and store, so
/// every screen reading `coRiderVoiceProvider` follows) and tells a live
/// voice session to switch (`change_voice`). A session that isn't open picks
/// it up on its next connect. Both the onboarding step and Settings save
/// through here.
void saveCoRiderVoice(WidgetRef ref, CoRiderVoice voice) {
  ref.read(coRiderVoiceProvider.notifier).select(voice);
  ref.read(voiceSessionProvider.notifier).applyVoice(voice);
}
