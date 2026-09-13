import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../providers/summary_stream_provider.dart';

/// The shift summary the co-rider streams in (`summary_chunk` events). The
/// LeMUR-powered post-shift report lands in Checkpoint 3.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryStreamProvider);
    if (summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(VoiceOpsSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your shift summary',
                style: VoiceOpsText.headline,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: VoiceOpsSpacing.sm),
              Text(
                'Ask your co-rider "how did my shift go?" and it appears here.',
                style: VoiceOpsText.bodyMuted,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          VoiceOpsSpacing.gutter,
          VoiceOpsSize.orbBubble + VoiceOpsSpacing.xl,
          VoiceOpsSpacing.gutter,
          VoiceOpsSpacing.xl,
        ),
        child: GlassCard(
          padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.isComplete ? 'SHIFT SUMMARY' : 'SHIFT SUMMARY · LIVE',
                style: VoiceOpsText.caption,
              ),
              const SizedBox(height: VoiceOpsSpacing.md),
              Text(summary.text, style: VoiceOpsText.body),
            ],
          ),
        ),
      ),
    );
  }
}
