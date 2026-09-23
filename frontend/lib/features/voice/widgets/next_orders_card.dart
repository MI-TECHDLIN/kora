import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../app/router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/progress_meter.dart';
import '../../../providers/navigation_provider.dart';
import '../../../providers/order_queue_provider.dart';
import '../../../providers/queue_focus_provider.dart';
import '../../summary/data/order_queue.dart';

/// Opens the full queue on the Summary tab.
void _openQueue(WidgetRef ref) {
  ref.read(queueFocusRequestProvider.notifier).state = true;
  ref.read(navigationProvider).goTo(MainTab.summary);
}

/// A glance at the queue: the current order and the next few pending ones.
/// Tapping it opens the full queue on Summary. Hidden while there is nothing
/// queued, so Home stays as light as it was.
class NextOrdersCard extends ConsumerWidget {
  const NextOrdersCard({super.key});

  /// The current order plus this many pending ones.
  static const upcomingShown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(orderQueueProvider.select((s) => s.queue));
    final shown = queue.upNext(upcomingShown + 1);
    if (shown.isEmpty) return const SizedBox.shrink();
    final more = queue.counts.active + queue.counts.pending - shown.length;
    return Padding(
      padding: const EdgeInsets.only(top: KoraSpacing.lg),
      child: Semantics(
        button: true,
        label: 'Next orders. Open your full order queue.',
        excludeSemantics: true,
        child: InkWell(
          key: const Key('next-orders-card'),
          borderRadius: BorderRadius.circular(KoraRadius.card),
          onTap: () => _openQueue(ref),
          child: GlassCard(
            frosted: false,
            shadow: false,
            padding: const EdgeInsets.all(KoraSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('NEXT ORDERS', style: KoraText.caption),
                    ),
                    const Icon(
                      TablerIcons.chevronRight,
                      size: KoraSize.iconMd,
                      color: KoraColors.textMuted,
                    ),
                  ],
                ),
                for (final order in shown) _Line(order: order),
                if (more > 0) ...[
                  const SizedBox(height: KoraSpacing.sm),
                  Text(
                    '+ $more more',
                    key: const Key('next-orders-more'),
                    style: KoraText.label.copyWith(color: KoraColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.order});

  final QueueOrder order;

  @override
  Widget build(BuildContext context) {
    final active = order.state == OrderState.active;
    return Padding(
      key: Key('next-order-${order.deliveryId}'),
      padding: const EdgeInsets.only(top: KoraSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            active ? TablerIcons.route : TablerIcons.circle,
            size: KoraSize.iconMd,
            color: active ? KoraColors.primaryLight : KoraColors.textMuted,
          ),
          const SizedBox(width: KoraSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? '${order.title} · now' : order.title,
                  style: active ? KoraText.title : KoraText.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (order.address != null && order.recipientName != null)
                  Text(
                    order.address!,
                    style: KoraText.bodyMuted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (order.timeWindow != null) ...[
            const SizedBox(width: KoraSpacing.sm),
            Flexible(
              child: Text(
                order.timeWindow!,
                style: KoraText.label.copyWith(color: KoraColors.textFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "8 / 15 deliveries" with a slim bar. Only shown once a target is set;
/// tapping it opens Summary, where the target is changed.
class TargetIndicator extends ConsumerWidget {
  const TargetIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(orderQueueProvider.select((s) => s.queue));
    final target = queue.target;
    if (target == null) return const SizedBox.shrink();
    final label = '${queue.completed} / $target deliveries';
    return Padding(
      padding: const EdgeInsets.only(top: KoraSpacing.md),
      child: Semantics(
        button: true,
        label: '$label. Open your summary.',
        excludeSemantics: true,
        child: InkWell(
          key: const Key('target-indicator'),
          borderRadius: BorderRadius.circular(KoraRadius.card),
          onTap: () => ref.read(navigationProvider).goTo(MainTab.summary),
          child: GlassCard(
            frosted: false,
            shadow: false,
            padding: const EdgeInsets.symmetric(
              horizontal: KoraSpacing.lg,
              vertical: KoraSpacing.md,
            ),
            child: Row(
              children: [
                const Icon(
                  TablerIcons.target,
                  size: KoraSize.iconMd,
                  color: KoraColors.primaryLight,
                ),
                const SizedBox(width: KoraSpacing.md),
                Flexible(
                  child: Text(
                    label,
                    style: KoraText.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: KoraSpacing.md),
                Expanded(
                  child: ProgressMeter(
                    value: queue.targetFraction,
                    semanticLabel: label,
                    height: KoraSpacing.xs + 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
