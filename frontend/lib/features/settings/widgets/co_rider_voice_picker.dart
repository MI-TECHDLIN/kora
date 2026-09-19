import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../providers/co_rider_voice_provider.dart';
import '../../../providers/co_rider_voice_save.dart';
import '../../../providers/voice_preview_provider.dart';

/// Settings' co-rider voice picker: one compact row per voice, a check on
/// the draft choice, a "hear this voice" button, and a Save button. Tapping
/// a row only drafts it; Save commits it (`saveCoRiderVoice`), which also
/// switches a live conversation. Deliberately its own smaller component —
/// the post-sign-up voice-onboarding step (`features/voice_onboarding/`) has
/// a fancier picker, and the two are never shared.
class CoRiderVoicePicker extends ConsumerStatefulWidget {
  const CoRiderVoicePicker({super.key});

  @override
  ConsumerState<CoRiderVoicePicker> createState() => _CoRiderVoicePickerState();
}

class _CoRiderVoicePickerState extends ConsumerState<CoRiderVoicePicker> {
  /// The tapped, not-yet-saved voice; null while it just follows the saved one.
  CoRiderVoice? _draft;

  /// The voice just saved, for the confirmation line.
  CoRiderVoice? _justSaved;

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
    if (voice == (_draft ?? ref.read(coRiderVoiceProvider))) return;
    _preview.stop();
    setState(() {
      _draft = voice;
      _justSaved = null;
    });
  }

  void _save(CoRiderVoice voice) {
    _preview.stop();
    saveCoRiderVoice(ref, voice);
    setState(() {
      _draft = null;
      _justSaved = voice;
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(coRiderVoiceProvider);
    final selected = _draft ?? saved;
    final dirty = selected != saved;
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
              _VoiceRow(
                voice: voice,
                selected: voice == selected,
                onTap: () => _pick(voice),
              ),
          const SizedBox(height: KoraSpacing.sm),
        ],
        Text(
          _justSaved != null
              ? '${_justSaved!.label} is now your co-rider\'s voice.'
              : dirty
              ? 'Save to switch to ${selected.label}.'
              : 'Your co-rider speaks as ${saved.label}.',
          key: const Key('co-rider-voice-status'),
          style: KoraText.bodyMuted,
        ),
        const SizedBox(height: KoraSpacing.sm),
        PrimaryButton(
          key: const Key('co-rider-voice-save'),
          label: 'Save',
          expand: true,
          icon: TablerIcons.check,
          onPressed: dirty ? () => _save(selected) : null,
        ),
      ],
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
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
        borderRadius: BorderRadius.circular(KoraRadius.control),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: KoraSize.touchTarget),
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
              _VoicePreviewButton(
                voice: voice,
                active: selected,
                onSelect: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Hear this voice": drafts [voice] (if not already) and plays its bundled
/// clip through [voicePreviewProvider]. No mic, no voice socket, no
/// push-to-talk state; disabled while the clip isn't bundled.
class _VoicePreviewButton extends ConsumerWidget {
  const _VoicePreviewButton({
    required this.voice,
    required this.active,
    required this.onSelect,
  });

  final CoRiderVoice voice;
  final bool active;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(voicePreviewProvider).playing == voice;
    ref.watch(voicePreviewAvailabilityProvider);
    final controller = ref.read(voicePreviewProvider.notifier);
    final available = controller.canPlay(voice);

    return IconButton(
      key: Key('co-rider-voice-preview-${voice.name}'),
      tooltip: !available
          ? 'Preview coming soon'
          : playing
          ? 'Stop ${voice.label}'
          : "Hear ${voice.label}'s voice",
      constraints: const BoxConstraints(
        minWidth: KoraSize.touchTarget,
        minHeight: KoraSize.touchTarget,
      ),
      onPressed: available
          ? () {
              onSelect();
              controller.toggle(voice);
            }
          : null,
      icon: Icon(
        playing ? TablerIcons.playerStop : TablerIcons.playerPlay,
        size: KoraSize.iconMd,
        color: !available
            ? KoraColors.textMuted
            : active
            ? KoraColors.primaryLight
            : KoraColors.textMuted,
      ),
    );
  }
}
