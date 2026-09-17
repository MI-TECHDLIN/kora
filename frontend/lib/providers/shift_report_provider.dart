import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/voiceops_api.dart';
import '../features/summary/data/shift_report.dart';

/// The post-shift report for a shift id; null while the backend is still
/// generating it. Auto-disposes so returning to the Summary tab after a new
/// summary refetches; `ref.invalidate` retries.
final shiftReportProvider = FutureProvider.autoDispose
    .family<ShiftReport?, String>(
      (ref, shiftId) =>
          ref.watch(voiceOpsApiProvider).fetchShiftReport(shiftId),
    );
