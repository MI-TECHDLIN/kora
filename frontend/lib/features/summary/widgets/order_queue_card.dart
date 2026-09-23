import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../providers/order_queue_provider.dart';
import '../data/order_queue.dart';

/// The full order queue as a checklist: the active stop with its "Mark
/// completed" action, the pending stops after it, then completed ones folded
/// away and failed or rescheduled ones shown plainly.
class OrderQueueCard extends ConsumerStatefulWidget {
  const OrderQueueCard({super.key});

  @override
  ConsumerState<OrderQueueCard> createState() => _OrderQueueCardState();
}

class _OrderQueueCardState extends ConsumerState<OrderQueueCard> {
  bool _completedOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderQueueProvider);
    final queue = state.queue;
    final active = queue.active;
    final pending = queue.ordersIn(OrderState.pending);
    final completed = queue.ordersIn(OrderState.completed);
    final failed = queue.ordersIn(OrderState.failed);
    final rescheduled = queue.ordersIn(OrderState.rescheduled);
    final unfinished = [...failed, ...rescheduled]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));

    return GlassCard(
      key: const Key('order-queue'),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('ORDER QUEUE', style: KoraText.caption)),
              IconButton(
                key: const Key('queue-refresh'),
                tooltip: 'Refresh orders',
                onPressed: state.loading
                    ? null
                    : () => unawaited(
                        ref.read(orderQueueProvider.notifier).refresh(),
                      ),
                constraints: const BoxConstraints(
                  minWidth: KoraSize.touchTarget,
                  minHeight: KoraSize.touchTarget,
                ),
                icon: const Icon(
                  TablerIcons.refresh,
                  size: KoraSize.iconMd,
                  color: KoraColors.textMuted,
                ),
              ),
            ],
          ),
          if (queue.isEmpty)
            const _EmptyQueue()
          else ...[
            if (active != null) ...[
              _ActiveOrder(order: active),
              if (state.error case final message?) ...[
                const SizedBox(height: KoraSpacing.sm),
                Text(
                  message,
                  key: const Key('queue-error'),
                  style: KoraText.label.copyWith(color: KoraColors.danger),
                ),
              ],
            ],
            if (pending.isNotEmpty) ...[
              const SizedBox(height: KoraSpacing.lg),
              Text('UP NEXT · ${pending.length}', style: KoraText.caption),
              for (final order in pending) _OrderRow(order: order),
            ],
            if (unfinished.isNotEmpty) ...[
              const SizedBox(height: KoraSpacing.lg),
              Text(
                'FAILED OR RESCHEDULED · ${unfinished.length}',
                style: KoraText.caption,
              ),
              for (final order in unfinished) _OrderRow(order: order),
            ],
            if (completed.isNotEmpty) ...[
              const SizedBox(height: KoraSpacing.md),
              _SectionToggle(
                open: _completedOpen,
                title: 'COMPLETED · ${completed.length}',
                onTap: () => setState(() => _completedOpen = !_completedOpen),
              ),
              if (_completedOpen)
                for (final order in completed) _OrderRow(order: order),
            ],
          ],
        ],
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('queue-empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          TablerIcons.listCheck,
          size: KoraSize.iconLg,
          color: KoraColors.textMuted,
        ),
        const SizedBox(width: KoraSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No orders in your queue', style: KoraText.label),
              const SizedBox(height: KoraSpacing.xs),
              Text(
                'Orders assigned to you or accepted from an offer show up '
                'here as a checklist.',
                style: KoraText.bodyMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The stop being worked on, with the action to finish it.
class _ActiveOrder extends ConsumerWidget {
  const _ActiveOrder({required this.order});

  final QueueOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy =
        ref.watch(orderQueueProvider.select((s) => s.busyDeliveryId)) != null;
    return GlassCard(
      key: const Key('order-active'),
      frosted: false,
      shadow: false,
      fill: KoraColors.primaryTint,
      border: Border.all(
        color: KoraColors.primaryGlow,
        width: KoraGlass.borderWidth,
      ),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ACTIVE · STOP ${order.sequence}', style: KoraText.caption),
          const SizedBox(height: KoraSpacing.sm),
          Text(order.title, style: KoraText.title),
          ..._details(order),
          const SizedBox(height: KoraSpacing.md),
          PrimaryButton(
            key: const Key('mark-completed'),
            label: busy ? 'Marking completed...' : 'Mark completed',
            icon: TablerIcons.check,
            expand: true,
            onPressed: busy
                ? null
                : () => unawaited(
                    ref
                        .read(orderQueueProvider.notifier)
                        .complete(order.deliveryId),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Address, time window and ETA lines, each only when the order has it.
List<Widget> _details(QueueOrder order) => [
  if (order.recipientName != null && order.address != null)
    _Detail(icon: TablerIcons.mapPin, text: order.address!),
  if (order.timeWindow != null)
    _Detail(icon: TablerIcons.clock, text: order.timeWindow!),
  if (order.etaMinutes != null)
    _Detail(icon: TablerIcons.route, text: '${order.etaMinutes} min away'),
];

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KoraSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: KoraSize.iconSm, color: KoraColors.textMuted),
          const SizedBox(width: KoraSpacing.sm),
          Expanded(child: Text(text, style: KoraText.bodyMuted)),
        ],
      ),
    );
  }
}

/// One checklist line. The leading mark says the state: an empty circle for
/// pending, a tick for completed, a cross for failed.
class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final QueueOrder order;

  @override
  Widget build(BuildContext context) {
    final (icon, color, status) = switch (order.state) {
      OrderState.completed => (
        TablerIcons.circleCheck,
        KoraColors.success,
        'Completed',
      ),
      OrderState.failed => (TablerIcons.circleX, KoraColors.pink, 'Failed'),
      OrderState.rescheduled => (
        TablerIcons.calendarEvent,
        KoraColors.amber,
        'Rescheduled',
      ),
      _ => (TablerIcons.circle, KoraColors.textMuted, 'Pending'),
    };
    return Padding(
      key: Key('order-row-${order.deliveryId}'),
      padding: const EdgeInsets.only(top: KoraSpacing.md),
      child: Semantics(
        label: 'Stop ${order.sequence}, ${order.title}, $status',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: KoraSize.iconMd, color: color),
            const SizedBox(width: KoraSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${order.sequence}. ${order.title}',
                    style: KoraText.label,
                  ),
                  if (order.address != null && order.recipientName != null)
                    Text(order.address!, style: KoraText.bodyMuted),
                  if (order.timeWindow != null)
                    Text(
                      order.timeWindow!,
                      style: KoraText.label.copyWith(
                        color: KoraColors.textFaint,
                      ),
                    ),
                ],
              ),
            ),
            if (order.state == OrderState.failed ||
                order.state == OrderState.rescheduled)
              Text(status, style: KoraText.label.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _SectionToggle extends StatelessWidget {
  const _SectionToggle({
    required this.open,
    required this.title,
    required this.onTap,
  });

  final bool open;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: open,
      label: title,
      excludeSemantics: true,
      child: InkWell(
        key: const Key('queue-completed-toggle'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: KoraSize.touchTarget),
          child: Row(
            children: [
              Expanded(child: Text(title, style: KoraText.caption)),
              Icon(
                open ? TablerIcons.chevronUp : TablerIcons.chevronDown,
                size: KoraSize.iconMd,
                color: KoraColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
