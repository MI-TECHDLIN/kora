import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' as rive;
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../providers/co_rider_voice_provider.dart';
import '../../../providers/co_rider_voice_save.dart';
import '../../../providers/voice_onboarding_provider.dart';
import '../../../providers/voice_preview_provider.dart';
import '../widgets/voice_character_rive.dart';

/// The one-time step right after sign-up: pick a co-rider voice, hear it,
/// and move on. Tapping a voice only highlights it as a draft (previews use
/// the draft); "Save" commits it (`saveCoRiderVoice`) and finishes the
/// step. [CoRiderVoice.fallback] is the default, so continuing without
/// touching anything is a valid path and completes the step too. Gated by
/// `voiceOnboardingProvider`
/// (frontend/lib/providers/voice_onboarding_provider.dart), never the
/// pre-sign-up onboarding flag in `onboarding_provider.dart`. The Settings
/// screen has its own smaller picker (`features/settings/widgets`) rather
/// than sharing this one.
///
/// Each voice gets its own small character slot (avatar-picker style) —
/// see [VoiceCharacterSlot]. The single-orb `MascotDisplay`
/// (`frontend/lib/mascot/`) is untouched and unused here.
class VoiceOnboardingScreen extends ConsumerStatefulWidget {
  const VoiceOnboardingScreen({super.key});

  @override
  ConsumerState<VoiceOnboardingScreen> createState() =>
      _VoiceOnboardingScreenState();
}

class _VoiceOnboardingScreenState extends ConsumerState<VoiceOnboardingScreen> {
  /// The tapped, not-yet-saved voice; null while nothing has been tapped.
  CoRiderVoice? _draft;

  late final VoicePreviewController _preview;

  @override
  void initState() {
    super.initState();
    _preview = ref.read(voicePreviewProvider.notifier);
  }

  @override
  void dispose() {
    // Leaving the screen ends the clip. Deferred: dispose can't change state.
    Future.microtask(_preview.stop);
    super.dispose();
  }

  void _pick(CoRiderVoice voice) {
    if (voice == _draft) return;
    _preview.stop();
    setState(() => _draft = voice);
  }

  void _finish() {
    final draft = _draft;
    if (draft != null && draft != ref.read(coRiderVoiceProvider)) {
      saveCoRiderVoice(ref, draft);
    }
    ref.read(voiceOnboardingProvider.notifier).complete();
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(coRiderVoiceProvider);
    final selected = _draft ?? saved;
    final previewing = ref.watch(voicePreviewProvider).playing;
    final hasChange = selected != saved;

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
                              speaking: voice == previewing,
                              onTap: () => _pick(voice),
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
              key: const Key('voice-onboarding-save'),
              label: hasChange ? 'Save' : 'Continue',
              expand: true,
              icon: hasChange ? TablerIcons.check : null,
              trailingIcon: hasChange ? null : TablerIcons.arrowRight,
              onPressed: _finish,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a voice's character art comes from now: the Rive file described in
/// `docs/kora-voice-characters-rive-spec.md`, drawn by
/// [VoiceCharacterSlot] when [VoiceCharacterSlot.rive] is set. Until that
/// file exists (or if any part of it is missing) every slot keeps its
/// neutral placeholder.
///
/// One voice's character: Rive art when [rive] is on and the file loads
/// with this voice's artboard, state machine and inputs; otherwise a
/// tinted-circle-with-initial placeholder. [selected] and [speaking] drive
/// the Rive inputs of the same names. Never the single reactive orb
/// (`frontend/lib/mascot/mascot_display.dart`).
class VoiceCharacterSlot extends ConsumerStatefulWidget {
  const VoiceCharacterSlot({
    super.key,
    required this.voice,
    this.selected = false,
    this.speaking = false,
    this.rive = false,
    this.size = _defaultSize,
  });

  final CoRiderVoice voice;
  final bool selected;

  /// This voice's preview clip is playing.
  final bool speaking;

  /// Try the Rive art. Only the voice step turns this on, so Settings never
  /// loads the file.
  final bool rive;
  final double size;

  static const _defaultSize = 64.0;

  @override
  ConsumerState<VoiceCharacterSlot> createState() => _VoiceCharacterSlotState();
}

class _VoiceCharacterSlotState extends ConsumerState<VoiceCharacterSlot> {
  VoiceCharacterRive? _art;
  rive.File? _artFile; // the file _art (or a failed attempt) was built from
  bool _artFailed = false;

  VoiceCharacterRive? _artFor(rive.File? file) {
    if (file == null) return null;
    if (!identical(file, _artFile)) {
      _art?.dispose();
      _art = null;
      _artFailed = false;
      _artFile = file;
    }
    if (_art == null && !_artFailed) {
      _art = VoiceCharacterRive.tryCreate(
        file,
        widget.voice,
        selected: widget.selected,
        speaking: widget.speaking,
      );
      _artFailed = _art == null;
    }
    _art?.update(selected: widget.selected, speaking: widget.speaking);
    return _art;
  }

  @override
  void dispose() {
    _art?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voice = widget.voice;
    final selected = widget.selected;
    final size = widget.size;
    final art = widget.rive
        ? _artFor(ref.watch(voiceCharactersFileProvider).valueOrNull)
        : null;
    if (art != null) {
      return SizedBox.square(dimension: size, child: art.build());
    }

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
          color: selected ? KoraColors.primaryLight : KoraGlass.border,
          width: selected ? KoraGlass.borderWidth * 2 : KoraGlass.borderWidth,
        ),
      ),
      child: Text(
        initial,
        style: KoraText.weight(KoraText.title, FontWeight.w700).copyWith(
          color: selected ? KoraColors.primaryLight : KoraColors.textMuted,
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
    required this.speaking,
    required this.onTap,
  });

  final CoRiderVoice voice;
  final bool selected;
  final bool speaking;
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
              VoiceCharacterSlot(
                voice: voice,
                selected: selected,
                speaking: speaking,
                rive: true,
              ),
              const SizedBox(height: KoraSpacing.xs),
              Text(
                voice.label,
                style: selected
                    ? KoraText.label.copyWith(color: KoraColors.primaryLight)
                    : KoraText.label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen voice, larger, with the "hear this voice" control: plays the
/// bundled clip through [voicePreviewProvider]. It never touches the mic,
/// the voice socket or push-to-talk.
class _SelectedVoicePreview extends ConsumerWidget {
  const _SelectedVoicePreview({required this.voice});

  final CoRiderVoice voice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(voicePreviewProvider);
    ref.watch(voicePreviewAvailabilityProvider);
    final controller = ref.read(voicePreviewProvider.notifier);
    final available = controller.canPlay(voice);
    final playing = preview.playing == voice;

    return GlassCard(
      frosted: false,
      padding: const EdgeInsets.all(KoraSpacing.md),
      child: Row(
        children: [
          VoiceCharacterSlot(
            voice: voice,
            selected: true,
            speaking: playing,
            rive: true,
            size: 48,
          ),
          const SizedBox(width: KoraSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(voice.label, style: KoraText.title),
                Text(
                  available
                      ? 'Tap to hear a short preview'
                      : 'Preview coming soon',
                  style: KoraText.bodyMuted,
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('voice-onboarding-preview-${voice.name}'),
            tooltip: !available
                ? 'Preview coming soon'
                : playing
                ? 'Stop ${voice.label}'
                : "Hear ${voice.label}'s voice",
            constraints: const BoxConstraints(
              minWidth: KoraSize.touchTarget,
              minHeight: KoraSize.touchTarget,
            ),
            onPressed: available ? () => controller.toggle(voice) : null,
            icon: Icon(
              playing ? TablerIcons.playerStop : TablerIcons.playerPlay,
              size: KoraSize.iconLg,
              color: available ? KoraColors.primaryLight : KoraColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
