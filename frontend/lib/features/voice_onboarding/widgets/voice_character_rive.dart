import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' as rive;

import '../../../providers/co_rider_voice_provider.dart';

/// The Rive-backed art for a voice character, used only by the post-sign-up
/// voice step (Settings never watches [voiceCharactersFileProvider], so it
/// never loads the file).
///
/// Contract with the captain's Rive file — keep in agreement with
/// docs/kora-voice-characters-rive-spec.md:
/// - file: [voiceCharactersAsset]
/// - one artboard per voice, named the voice's enum `name` (`alba`, `eve`…)
/// - state machine [voiceStateMachine] on each
/// - Boolean inputs [selectedInput] (this character is the selected one) and
///   [speakingInput] (its preview clip is playing)
///
/// Anything missing — the file (it doesn't exist yet), an artboard, the
/// state machine, or an input — makes [VoiceCharacterRive.tryCreate] return
/// null and the caller keeps its placeholder.
const voiceCharactersAsset = 'assets/rive/voice_characters.riv';
const voiceStateMachine = 'Voice';
const selectedInput = 'selected';
const speakingInput = 'speaking';

/// Loads the shared .riv once, or null when it is missing or the Rive
/// runtime is unavailable (e.g. `flutter test`). Tests override it.
final voiceCharactersFileProvider = FutureProvider<rive.File?>((ref) async {
  try {
    final file = await rive.File.asset(
      voiceCharactersAsset,
      riveFactory: rive.Factory.rive,
    );
    if (file != null) ref.onDispose(file.dispose);
    return file;
  } catch (error) {
    debugPrint(
      'Voice characters: $voiceCharactersAsset unavailable ($error); '
      'using placeholders.',
    );
    return null;
  }
});

/// One live character, as the slot sees it. [VoiceCharacterRive] is the real
/// one; tests inject fakes through [voiceArtFactoryProvider].
abstract class VoiceArt {
  void update({required bool selected, required bool speaking});
  void dispose();
  Widget build();
}

/// Builds the art for one voice, or null to keep the placeholder.
typedef VoiceArtFactory =
    VoiceArt? Function(
      CoRiderVoice voice, {
      required bool selected,
      required bool speaking,
    });

/// How a slot gets a voice's art: null until the .riv loads (or forever if
/// it is missing), then [VoiceCharacterRive.tryCreate] on the loaded file.
/// Only slots with `rive: true` watch it, so Settings never loads the file.
/// Tests override this to avoid the native Rive runtime.
final voiceArtFactoryProvider = Provider<VoiceArtFactory?>((ref) {
  final file = ref.watch(voiceCharactersFileProvider).valueOrNull;
  if (file == null) return null;
  return (voice, {required selected, required speaking}) =>
      VoiceCharacterRive.tryCreate(
        file,
        voice,
        selected: selected,
        speaking: speaking,
      );
});

/// One live character: [voice]'s artboard, its `Voice` state machine, and
/// the two inputs.
class VoiceCharacterRive implements VoiceArt {
  VoiceCharacterRive._(this.controller, this._selected, this._speaking);

  final rive.RiveWidgetController controller;
  final rive.BooleanInput _selected;
  final rive.BooleanInput _speaking;

  /// Returns null unless the file matches the contract above.
  static VoiceCharacterRive? tryCreate(
    rive.File file,
    CoRiderVoice voice, {
    required bool selected,
    required bool speaking,
  }) {
    rive.RiveWidgetController? controller;
    try {
      controller = rive.RiveWidgetController(
        file,
        artboardSelector: rive.ArtboardSelector.byName(voice.name),
        stateMachineSelector: rive.StateMachineSelector.byName(
          voiceStateMachine,
        ),
      );
      final machine = controller.stateMachine;
      // The spec (docs/kora-voice-characters-rive-spec.md) fixes these as
      // state-machine Boolean inputs, not data-binding properties.
      // ignore: deprecated_member_use
      final selectedBool = machine.boolean(selectedInput);
      // ignore: deprecated_member_use
      final speakingBool = machine.boolean(speakingInput);
      if (selectedBool == null || speakingBool == null) {
        throw StateError(
          'missing Boolean input "$selectedInput" or "$speakingInput"',
        );
      }
      return VoiceCharacterRive._(controller, selectedBool, speakingBool)
        ..update(selected: selected, speaking: speaking);
    } catch (error) {
      debugPrint('Voice character ${voice.name} failed ($error); placeholder.');
      controller?.dispose();
      return null;
    }
  }

  @override
  void update({required bool selected, required bool speaking}) {
    if (_selected.value != selected) _selected.value = selected;
    if (_speaking.value != speaking) _speaking.value = speaking;
    controller.scheduleRepaint();
  }

  @override
  void dispose() => controller.dispose();

  @override
  Widget build() =>
      rive.RiveWidget(controller: controller, fit: rive.Fit.contain);
}
