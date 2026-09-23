import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/voiceops_api.dart';
import '../features/summary/data/shift_report.dart';

class ShiftReportPollingConfig {
  const ShiftReportPollingConfig({
    this.processingRetryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 15),
    ],
  });

  /// Delays after each `processing` response. Once exhausted, the provider
  /// returns null so the screen can offer a manual retry.
  final List<Duration> processingRetryDelays;
}

final shiftReportPollingConfigProvider = Provider<ShiftReportPollingConfig>(
  (ref) => const ShiftReportPollingConfig(),
);

/// The post-shift report for a shift id; null while the backend is still
/// generating it after the bounded polling window. Auto-disposes so returning
/// to the Summary tab after a new summary refetches; `ref.invalidate` retries.
final shiftReportProvider = FutureProvider.autoDispose
    .family<ShiftReport?, String>((ref, shiftId) async {
      final api = ref.watch(koraApiProvider);
      final config = ref.watch(shiftReportPollingConfigProvider);
      var disposed = false;
      ref.onDispose(() => disposed = true);

      for (var attempt = 0; ; attempt++) {
        final report = await api.fetchShiftReport(shiftId);
        if (report != null || disposed) return report;

        if (attempt >= config.processingRetryDelays.length) return null;
        await Future<void>.delayed(config.processingRetryDelays[attempt]);
        if (disposed) return null;
      }
    });
