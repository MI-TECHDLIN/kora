import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime/voice_events.dart';

class TranscriptLine {
  const TranscriptLine(this.role, this.text);
  final SpeakerRole role;
  final String text;
}

/// The conversation so far, oldest first, from the voice session's
/// `transcript` events. Capped so a long shift doesn't grow it forever.
final transcriptProvider =
    StateNotifierProvider<TranscriptNotifier, List<TranscriptLine>>(
      (ref) => TranscriptNotifier(),
    );

class TranscriptNotifier extends StateNotifier<List<TranscriptLine>> {
  TranscriptNotifier() : super(const []);

  static const _maxLines = 50;

  void add(SpeakerRole role, String text) {
    final next = [...state, TranscriptLine(role, text)];
    state = next.length > _maxLines
        ? next.sublist(next.length - _maxLines)
        : next;
  }

  void clear() => state = const [];
}
