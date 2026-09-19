import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../providers/co_rider_voice_provider.dart';
import '../../../providers/push_to_talk_provider.dart';
import '../../../providers/voice_session_provider.dart';

/// Settings' co-rider voice picker: one compact row per voice, a check on
/// the current choice, and a "test this voice" button. Deliberately its own
/// smaller component — the post-sign-up voice-onboarding step
/// (`features/voice_onboarding/`) has a fancier picker, and the two are
/// never shared.
class CoRiderVoicePicker extends ConsumerWidget {
  const CoRiderVoicePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(coRiderVoiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final accent in CoRiderAccent.values) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: KoraSpacing.xs),
            child: Text(accent.label, style: KoraText.bodyMuted),
          ),
          for (final voice in CoRiderVoice.values)
            if (voice.accent == accent)
              _VoiceRow(voice: voice, selected: voice == selected),
          const SizedBox(height: KoraSpacing.sm),
        ],
        Text(
          'Applies to your next conversation.',
          style: KoraText.bodyMuted,
        ),
      ],
    );
  }
}

class _VoiceRow extends ConsumerWidget {
  const _VoiceRow({required this.voice, required this.selected});

  final CoRiderVoice voice;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      selected: selected,
      label: voice.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(KoraRadius.control),
        onTap: () => ref.read(coRiderVoiceProvider.notifier).select(voice),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: KoraSize.touchTarget,
          ),
          child: Row(
            children: [
              Icon(
                selected ? TablerIcons.circleCheck : TablerIcons.circle,
                size: KoraSize.iconMd,
                color: selected
                    ? KoraColors.primaryLight
                    : KoraColors.textMuted,
              ),
              const SizedBox(width: KoraSpacing.sm),
              Expanded(child: Text(voice.label, style: KoraText.label)),
              _VoicePreviewButton(voice: voice, active: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Test this voice": selects [voice] (if not already) and opens a preview
/// through the app's existing voice-socket connection
/// (`voiceSessionProvider`), the same mechanism the push-to-talk button
/// uses. Its icon reflects [pushToTalkProvider] only while [active] — the
/// socket carries a single, app-wide conversation.
class _VoicePreviewButton extends ConsumerWidget {
  const _VoicePreviewButton({required this.voice, required this.active});

  final CoRiderVoice voice;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = active ? ref.watch(pushToTalkProvider) : PushToTalkState.idle;
    final (icon, label) = switch (state) {
      PushToTalkState.idle => (
        TablerIcons.microphone,
        "Test ${voice.label}'s voice",
      ),
      PushToTalkState.recording => (
        TablerIcons.microphoneFilled,
        'Listening. Tap to stop',
      ),
      PushToTalkState.processing => (TablerIcons.loader2, 'Working on it'),
      PushToTalkState.speaking => (
        TablerIcons.waveSine,
        '${voice.label} speaking',
      ),
    };

    return IconButton(
      key: Key('co-rider-voice-preview-${voice.name}'),
      tooltip: label,
      constraints: const BoxConstraints(
        minWidth: KoraSize.touchTarget,
        minHeight: KoraSize.touchTarget,
      ),
      onPressed: () {
        ref.read(coRiderVoiceProvider.notifier).select(voice);
        ref.read(voiceSessionProvider.notifier).onPushToTalk();
      },
      icon: Icon(
        icon,
        size: KoraSize.iconMd,
        color: active ? KoraColors.primaryLight : KoraColors.textMuted,
      ),
    );
  }
}
