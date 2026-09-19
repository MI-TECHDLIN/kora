import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../providers/co_rider_voice_provider.dart';
import '../../../providers/push_to_talk_provider.dart';
import '../../../providers/voice_onboarding_provider.dart';
import '../../../providers/voice_session_provider.dart';

/// The one-time step right after sign-up: pick a co-rider voice, try it,
/// and move on. [CoRiderVoice.fallback] starts selected, so continuing
/// without touching anything is a valid path — there is no separate skip
/// button. Gated by `voiceOnboardingProvider`
/// (frontend/lib/providers/voice_onboarding_provider.dart), never the
/// pre-sign-up onboarding flag in `onboarding_provider.dart`. The Settings
/// screen has its own smaller picker (`features/settings/widgets`) rather
/// than sharing this one.
///
/// Each voice gets its own small character slot (avatar-picker style)
/// instead of one orb reacting to the selection — see
/// [voiceCharacterAsset]. The single-orb `MascotDisplay`
/// (`frontend/lib/mascot/`) is untouched and unused here.
class VoiceOnboardingScreen extends ConsumerWidget {
  const VoiceOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(coRiderVoiceProvider);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                KoraSpacing.gutter,
                KoraSpacing.xl,
                KoraSpacing.gutter,
                KoraSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Meet your co-rider',
                      style: KoraText.headline,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: KoraSpacing.sm),
                  Text(
                    'Pick a voice for the road ahead. You can always change '
                    'it later in Settings.',
                    style: KoraText.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: KoraSpacing.xl),
                  for (final accent in CoRiderAccent.values) ...[
                    Text(accent.label, style: KoraText.caption),
                    const SizedBox(height: KoraSpacing.md),
                    Wrap(
                      spacing: KoraSpacing.md,
                      runSpacing: KoraSpacing.md,
                      children: [
                        for (final voice in CoRiderVoice.values)
                          if (voice.accent == accent)
                            _VoiceCharacterOption(
                              voice: voice,
                              selected: voice == selected,
                              onTap: () => ref
                                  .read(coRiderVoiceProvider.notifier)
                                  .select(voice),
                            ),
                      ],
                    ),
                    const SizedBox(height: KoraSpacing.lg),
                  ],
                  const SizedBox(height: KoraSpacing.sm),
                  _SelectedVoicePreview(voice: selected),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KoraSpacing.gutter,
              0,
              KoraSpacing.gutter,
              KoraSpacing.lg,
            ),
            child: PrimaryButton(
              label: 'Continue',
              expand: true,
              trailingIcon: TablerIcons.arrowRight,
              onPressed: () =>
                  ref.read(voiceOnboardingProvider.notifier).complete(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a voice's character art will live once one is designed in Rive
/// Desktop (AGENTS.md reserves `.riv` authoring to the captain). Every voice
/// returns null today, so [VoiceCharacterSlot] always shows its neutral
/// placeholder; dropping a real asset path in here is the only change
/// needed to show it — no widget above this needs to change.
String? voiceCharacterAsset(CoRiderVoice voice) => null;

/// One voice's character art, or a tinted-circle-with-initial placeholder
/// when [voiceCharacterAsset] has nothing for it yet. Never the single
/// reactive orb (`frontend/lib/mascot/mascot_display.dart`) — each voice
/// gets its own distinct, static slot.
class VoiceCharacterSlot extends StatelessWidget {
  const VoiceCharacterSlot({
    super.key,
    required this.voice,
    this.selected = false,
    this.size = _defaultSize,
  });

  final CoRiderVoice voice;
  final bool selected;
  final double size;

  static const _defaultSize = 64.0;

  @override
  Widget build(BuildContext context) {
    final asset = voiceCharacterAsset(voice);
    final initial = voice.label.isEmpty ? '?' : voice.label[0].toUpperCase();

    return AnimatedContainer(
      duration: KoraMotion.base,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? KoraColors.primaryTint : KoraColors.elevated,
        border: Border.all(
          color: selected
              ? KoraColors.primaryLight
              : KoraGlass.border,
          width: selected
              ? KoraGlass.borderWidth * 2
              : KoraGlass.borderWidth,
        ),
      ),
      child: asset != null
          ? ClipOval(
              child: Image.asset(
                asset,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            )
          : Text(
              initial,
              style: KoraText.weight(KoraText.title, FontWeight.w700)
                  .copyWith(
                    color: selected
                        ? KoraColors.primaryLight
                        : KoraColors.textMuted,
                  ),
            ),
    );
  }
}

/// One tappable slot in the avatar-picker grid: the character above its
/// voice's name.
class _VoiceCharacterOption extends StatelessWidget {
  const _VoiceCharacterOption({
    required this.voice,
    required this.selected,
    required this.onTap,
  });

  final CoRiderVoice voice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: voice.label,
      excludeSemantics: true,
      child: InkWell(
        key: Key('voice-onboarding-option-${voice.name}'),
        borderRadius: BorderRadius.circular(KoraRadius.control),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(KoraSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VoiceCharacterSlot(voice: voice, selected: selected),
              const SizedBox(height: KoraSpacing.xs),
              Text(
                voice.label,
                style: selected
                    ? KoraText.label.copyWith(
                        color: KoraColors.primaryLight,
                      )
                    : KoraText.label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The currently selected voice, larger, with the "test this voice"
/// control: opens a preview through the app's existing voice-socket
/// connection (`voiceSessionProvider`), the same mechanism the push-to-talk
/// button uses — no separate audio pipeline.
class _SelectedVoicePreview extends ConsumerWidget {
  const _SelectedVoicePreview({required this.voice});

  final CoRiderVoice voice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pushToTalkProvider);
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

    return GlassCard(
      frosted: false,
      padding: const EdgeInsets.all(KoraSpacing.md),
      child: Row(
        children: [
          VoiceCharacterSlot(voice: voice, selected: true, size: 48),
          const SizedBox(width: KoraSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(voice.label, style: KoraText.title),
                Text('Tap to hear a short preview', style: KoraText.bodyMuted),
              ],
            ),
          ),
          IconButton(
            key: Key('voice-onboarding-preview-${voice.name}'),
            tooltip: label,
            constraints: const BoxConstraints(
              minWidth: KoraSize.touchTarget,
              minHeight: KoraSize.touchTarget,
            ),
            onPressed: () =>
                ref.read(voiceSessionProvider.notifier).onPushToTalk(),
            icon: Icon(
              icon,
              size: KoraSize.iconLg,
              color: KoraColors.primaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
