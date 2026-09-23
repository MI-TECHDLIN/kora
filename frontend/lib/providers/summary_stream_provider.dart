import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The spoken shift summary as it streams in (`summary_chunk` events).
class SummaryStream {
  const SummaryStream({this.text = '', this.isComplete = false});
  final String text;
  final bool isComplete;
}

final summaryStreamProvider =
    StateNotifierProvider<SummaryStreamNotifier, SummaryStream?>(
      (ref) => SummaryStreamNotifier(),
    );

class SummaryStreamNotifier extends StateNotifier<SummaryStream?> {
  SummaryStreamNotifier() : super(null);

  /// Appends a chunk; the first chunk after a finished summary starts a new
  /// one.
  void append(String text, {required bool isFinal}) {
    final current = state;
    final base = current == null || current.isComplete ? '' : current.text;
    state = SummaryStream(text: base + text, isComplete: isFinal);
  }

  /// Clears any streamed summary text. Called when a new shift starts, so a
  /// driver never sees a previous shift's summary bleed into a new one.
  void reset() => state = null;
}
