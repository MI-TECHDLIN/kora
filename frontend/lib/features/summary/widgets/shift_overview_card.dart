import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/progress_meter.dart';
import '../data/order_queue.dart';
import 'shift_report_view.dart';

/// "2 of 5 deliveries completed", or a plain "No orders yet".
String shiftProgressLabel(OrderQueue queue) {
  final total = queue.counts.total;
  if (total == 0) return 'No orders yet';
  return '${queue.completed} of $total '
      '${total == 1 ? 'delivery' : 'deliveries'} completed';
}

/// The Summary tab's default state: today's activity, the shift's status,
/// operational progress and the completed / active / pending counts. It
/// reads well with no shift, a shift with no orders, and a shift mid-way, so
/// the tab is useful before any report exists.
class ShiftOverviewCard extends StatelessWidget {
  const ShiftOverviewCard({
    super.key,
    required this.queue,
    required this.shiftActive,
  });

  final OrderQueue queue;
  final bool shiftActive;

  @override
  Widget build(BuildContext context) {
    final counts = queue.counts;
    final progress = shiftProgressLabel(queue);
    final others = [
      if (counts.failed > 0) '${counts.failed} failed',
      if (counts.rescheduled > 0) '${counts.rescheduled} rescheduled',
    ];
    return GlassCard(
      key: const Key('shift-overview'),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text("TODAY'S ACTIVITY", style: KoraText.caption),
              ),
              _StatusPill(active: shiftActive),
            ],
          ),
          const SizedBox(height: KoraSpacing.md),
          Text(
            progress,
            key: const Key('shift-progress-text'),
            style: KoraText.title,
          ),
          const SizedBox(height: KoraSpacing.sm),
          ProgressMeter(
            key: const Key('shift-progress-meter'),
            value: queue.shiftFraction,
            semanticLabel: progress,
          ),
          const SizedBox(height: KoraSpacing.md),
          Row(
            children: [
              for (final (index, stat) in <StatData>[
                (
                  icon: TablerIcons.circleCheck,
                  color: KoraColors.success,
                  value: '${counts.completed}',
                  label: 'Completed',
                ),
                (
                  icon: TablerIcons.route,
                  color: KoraColors.primaryLight,
                  value: '${counts.active}',
                  label: 'Active',
                ),
                (
                  icon: TablerIcons.hourglass,
                  color: KoraColors.amber,
                  value: '${counts.pending}',
                  label: 'Pending',
                ),
              ].indexed) ...[
                if (index > 0) const SizedBox(width: KoraSpacing.sm),
                Expanded(child: StatTile(stat: stat)),
              ],
            ],
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: KoraSpacing.sm),
            Text(
              others.join(' · '),
              key: const Key('shift-other-counts'),
              style: KoraText.label.copyWith(color: KoraColors.textMuted),
            ),
          ],
          const SizedBox(height: KoraSpacing.md),
          Text(
            'Your full shift summary is generated as you complete orders. '
            'Ask your co-rider "how did my shift go?" any time.',
            key: const Key('summary-explainer'),
            style: KoraText.bodyMuted,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? KoraColors.success : KoraColors.textFaint;
    return Row(
      key: const Key('shift-status'),
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: KoraSize.listDot),
        ),
        const SizedBox(width: KoraSpacing.sm),
        Text(
          active ? 'Shift active' : 'No shift yet',
          style: KoraText.label.copyWith(color: color),
        ),
      ],
    );
  }
}
