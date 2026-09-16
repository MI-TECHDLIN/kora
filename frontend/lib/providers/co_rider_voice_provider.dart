import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The English stock voices AssemblyAI's Voice Agent API documents, sent as
/// `?voice=<name>` on the voice socket. The backend sets
/// `session.output.voice` once at session start, so a change applies to the
/// next conversation. See docs/backend-handoff/voice-tone-selection.md.
enum CoRiderVoice {
  alba('Alba', CoRiderAccent.american),
  eve('Eve', CoRiderAccent.american),
  george('George', CoRiderAccent.american),
  jane('Jane', CoRiderAccent.american),
  jean('Jean', CoRiderAccent.american),
  mary('Mary', CoRiderAccent.american),
  michael('Michael', CoRiderAccent.american),
  anna('Anna', CoRiderAccent.british),
  charles('Charles', CoRiderAccent.british),
  paul('Paul', CoRiderAccent.british),
  vera('Vera', CoRiderAccent.british);

  const CoRiderVoice(this.label, this.accent);

  final String label;
  final CoRiderAccent accent;

  /// Matches the voice the backend hardcodes today.
  static const fallback = anna;
}

enum CoRiderAccent {
  american('American English'),
  british('British English');

  const CoRiderAccent(this.label);

  final String label;
}

abstract interface class CoRiderVoiceStore {
  Future<CoRiderVoice?> load();
  Future<void> save(CoRiderVoice voice);
}

class SharedPreferencesCoRiderVoiceStore implements CoRiderVoiceStore {
  const SharedPreferencesCoRiderVoiceStore();

  static const _key = 'co_rider_voice';

  @override
  Future<CoRiderVoice?> load() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return CoRiderVoice.values
        .where((voice) => voice.name == value)
        .firstOrNull;
  }

  @override
  Future<void> save(CoRiderVoice voice) async {
    await (await SharedPreferences.getInstance()).setString(_key, voice.name);
  }
}

final coRiderVoiceStoreProvider = Provider<CoRiderVoiceStore>(
  (ref) => const SharedPreferencesCoRiderVoiceStore(),
);

final coRiderVoiceProvider =
    StateNotifierProvider<CoRiderVoiceController, CoRiderVoice>(
      CoRiderVoiceController.new,
    );

/// Anna until the saved choice loads.
class CoRiderVoiceController extends StateNotifier<CoRiderVoice> {
  CoRiderVoiceController(this._ref) : super(CoRiderVoice.fallback) {
    loaded = _loadSaved();
  }

  final Ref _ref;
  bool _selectedLocally = false;

  /// Completes once the saved choice is applied (or found missing), so the
  /// voice socket doesn't open with the default ahead of it.
  late final Future<void> loaded;

  Future<void> _loadSaved() async {
    try {
      final saved = await _ref.read(coRiderVoiceStoreProvider).load();
      if (!_selectedLocally && saved != null && mounted) state = saved;
    } catch (_) {
      // No readable preference: keep Anna.
    }
  }

  void select(CoRiderVoice voice) {
    _selectedLocally = true;
    state = voice;
    unawaited(_save(voice));
  }

  Future<void> _save(CoRiderVoice voice) async {
    try {
      await _ref.read(coRiderVoiceStoreProvider).save(voice);
    } catch (_) {
      // Keep the choice for this run. A later choice retries persistence.
    }
  }
}
