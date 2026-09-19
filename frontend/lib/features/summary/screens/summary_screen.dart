import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/api/voiceops_api.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../providers/shift_provider.dart';
import '../../../providers/shift_report_provider.dart';
import '../../../providers/summary_stream_provider.dart';
import '../widgets/shift_report_view.dart';

/// The shift summary. While the co-rider streams it in (`summary_chunk`
/// events) this shows the live text; once it is complete, the structured
/// post-shift report (`GET /v1/shift/{shift_id}/report`) takes over.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryStreamProvider);
    if (summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KoraSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your shift summary',
                style: KoraText.headline,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KoraSpacing.sm),
              Text(
                'Ask your co-rider "how did my shift go?" and it appears here.',
                style: KoraText.bodyMuted,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    final shiftId = ref.watch(shiftProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KoraSpacing.gutter,
          KoraSize.orbBubble + KoraSpacing.xl,
          KoraSpacing.gutter,
          KoraSpacing.xl,
        ),
        child: !summary.isComplete || shiftId == null
            ? RecapCard(text: summary.text, live: !summary.isComplete)
            : _FinishedShift(shiftId: shiftId, recap: summary.text),
      ),
    );
  }
}

/// A complete summary: the report once the backend has it, with the recap
/// and a loading, not-ready or error card until then.
class _FinishedShift extends ConsumerWidget {
  const _FinishedShift({required this.shiftId, required this.recap});

  final String shiftId;
  final String recap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(shiftReportProvider(shiftId));
    void retry() => ref.invalidate(shiftReportProvider(shiftId));

    final Widget status;
    switch (report) {
      case AsyncData(value: final ready?):
        return ShiftReportView(report: ready, recap: recap);
      case AsyncError(:final error):
        status = _ReportStatus(
          key: const Key('report-error'),
          icon: TablerIcons.alertTriangle,
          message: error is ApiException
              ? error.message
              : "Couldn't load your shift report.",
          onRetry: retry,
        );
      case AsyncData():
        status = _ReportStatus(
          key: const Key('report-processing'),
          icon: TablerIcons.hourglass,
          message: 'Your co-rider is still putting the numbers together.',
          onRetry: retry,
        );
      default:
        status = const _ReportStatus(
          key: Key('report-loading'),
          message: 'Building your shift report...',
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecapCard(text: recap, live: false),
        const SizedBox(height: KoraSpacing.md),
        status,
      ],
    );
  }
}

/// Loading (no [onRetry]), not-ready, or failed report fetch.
class _ReportStatus extends StatelessWidget {
  const _ReportStatus({
    super.key,
    required this.message,
    this.icon,
    this.onRetry,
  });

  final String message;
  final IconData? icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: KoraSize.iconMd,
                child: icon == null
                    ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: KoraColors.primaryLight,
                      )
                    : Icon(
                        icon,
                        size: KoraSize.iconMd,
                        color: KoraColors.primaryLight,
                      ),
              ),
              const SizedBox(width: KoraSpacing.md),
              Expanded(child: Text(message, style: KoraText.bodyMuted)),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: KoraSpacing.md),
            PrimaryButton(
              label: 'Check again',
              icon: TablerIcons.refresh,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
