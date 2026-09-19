import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'co_rider_voice_provider.dart';

/// Plays a bundled preview clip of a co-rider voice. This is the only seam
/// the pickers use to "hear a voice": it opens no socket, starts no shift,
/// and never touches the microphone or `pushToTalkProvider` — the live
/// conversation (`voice_session_provider.dart`) is a separate path.
///
/// Clips live at [assetFor] (see `assets/audio/voice_previews/README.md`).
/// Tests override [voicePreviewPlayerProvider].
abstract interface class VoicePreviewPlayer {
  /// The voices that have a clip bundled right now.
  Future<Set<CoRiderVoice>> availableVoices();

  /// Plays [voice]'s clip; completes when it ends or [stop] cuts it off.
  /// Throws if the clip can't be played.
  Future<void> play(CoRiderVoice voice);

  Future<void> stop();

  Future<void> dispose();
}

const _clipDirectory = 'assets/audio/voice_previews';

/// Where [voice]'s preview clip is bundled.
String voicePreviewAssetFor(CoRiderVoice voice) =>
    '$_clipDirectory/${voice.name}.mp3';

class JustAudioVoicePreviewPlayer implements VoicePreviewPlayer {
  // Created on first play, like the reply playback in core/audio.
  AudioPlayer? _player;

  @override
  Future<Set<CoRiderVoice>> availableVoices() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().toSet();
    return {
      for (final voice in CoRiderVoice.values)
        if (assets.contains(voicePreviewAssetFor(voice))) voice,
    };
  }

  @override
  Future<void> play(CoRiderVoice voice) async {
    final player = _player ??= AudioPlayer();
    await player.setAsset(voicePreviewAssetFor(voice));
    await player.seek(Duration.zero);
    // Completes when the clip ends, or when stop() interrupts it.
    await player.play();
  }

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> dispose() async => _player?.dispose();
}

final voicePreviewPlayerProvider = Provider<VoicePreviewPlayer>((ref) {
  final player = JustAudioVoicePreviewPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// The voices with a bundled clip. Empty on failure, so a broken bundle
/// disables previews instead of throwing.
final voicePreviewAvailabilityProvider = FutureProvider<Set<CoRiderVoice>>((
  ref,
) async {
  try {
    return await ref.watch(voicePreviewPlayerProvider).availableVoices();
  } catch (e) {
    debugPrint('Voice previews unavailable: $e');
    return const {};
  }
});

class VoicePreviewState {
  const VoicePreviewState({this.playing, this.failed = const {}});

  /// The voice whose clip is playing right now.
  final CoRiderVoice? playing;

  /// Voices whose clip turned out unplayable this run.
  final Set<CoRiderVoice> failed;
}

/// Auto-disposed with the screen that watches it, which stops the clip when
/// the driver leaves.
final voicePreviewProvider =
    StateNotifierProvider.autoDispose<
      VoicePreviewController,
      VoicePreviewState
    >(VoicePreviewController.new);

class VoicePreviewController extends StateNotifier<VoicePreviewState> {
  VoicePreviewController(this._ref) : super(const VoicePreviewState()) {
    _player = _ref.read(voicePreviewPlayerProvider);
  }

  final Ref _ref;
  late final VoicePreviewPlayer _player;

  /// Bumped by every play and stop, so a clip that ends late can't clear a
  /// newer one's state.
  int _generation = 0;

  /// Whether [voice] has a clip that can play.
  bool canPlay(CoRiderVoice voice) =>
      !state.failed.contains(voice) &&
      (_ref
              .read(voicePreviewAvailabilityProvider)
              .valueOrNull
              ?.contains(voice) ??
          false);

  /// Plays [voice], or stops it if it is already playing. Any other clip
  /// stops first.
  Future<void> toggle(CoRiderVoice voice) async {
    if (state.playing == voice) return stop();
    await stop();
    if (!canPlay(voice)) return;
    final generation = ++_generation;
    state = VoicePreviewState(playing: voice, failed: state.failed);
    try {
      await _player.play(voice);
    } catch (e) {
      debugPrint('Voice preview for ${voice.name} failed: $e');
      if (mounted) {
        state = VoicePreviewState(failed: {...state.failed, voice});
      }
      return;
    }
    if (mounted && generation == _generation) {
      state = VoicePreviewState(failed: state.failed);
    }
  }

  Future<void> stop() async {
    if (!mounted) return;
    _generation++;
    if (state.playing != null) {
      state = VoicePreviewState(failed: state.failed);
    }
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('Voice preview stop failed: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_player.stop().catchError((Object _) {}));
    super.dispose();
  }
}
