import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/glass_card.dart';
import '../providers/task_progress_provider.dart';

/// Global progress for tool calls in the current voice turn.
///
/// The authenticated WebSocket is the source of these ephemeral steps.
/// Supabase remains the durable source for the underlying shift and delivery.
class TaskProgressCard extends ConsumerWidget {
  const TaskProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(taskProgressProvider);
    final show = steps.isNotEmpty;
    final complete = steps
        .where((step) => step.status == TaskStepStatus.done)
        .length;
    final allDone = show && complete == steps.length;

    return IgnorePointer(
      child: Semantics(
        container: show,
        liveRegion: show,
        label: show
            ? allDone
                  ? 'Task complete. $complete of ${steps.length} steps done.'
                  : 'Working. $complete of ${steps.length} steps done.'
            : null,
        child: AnimatedSlide(
          offset: show ? Offset.zero : const Offset(0, 1.1),
          duration: KoraMotion.slow,
          curve: KoraMotion.standard,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: KoraMotion.base,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KoraSpacing.gutter,
                  0,
                  KoraSpacing.gutter,
                  KoraSize.taskCardBottom,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: KoraSize.taskCardMaxWidth,
                  ),
                  child: GlassCard(
                    key: const Key('task-progress-card'),
                    fill: KoraColors.raised.withValues(alpha: 0.94),
                    padding: const EdgeInsets.all(KoraSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              allDone
                                  ? TablerIcons.circleCheck
                                  : TablerIcons.sparkles,
                              size: KoraSize.iconMd,
                              color: allDone
                                  ? KoraColors.success
                                  : KoraColors.primaryLight,
                            ),
                            const SizedBox(width: KoraSpacing.sm),
                            Expanded(
                              child: Text(
                                allDone ? 'Task complete' : 'Co-rider working',
                                style: KoraText.title,
                              ),
                            ),
                            Text(
                              '$complete/${steps.length}',
                              style: KoraText.caption,
                            ),
                          ],
                        ),
                        const SizedBox(height: KoraSpacing.md),
                        for (var index = 0; index < steps.length; index++) ...[
                          _TaskStepRow(step: steps[index]),
                          if (index != steps.length - 1)
                            const SizedBox(height: KoraSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskStepRow extends StatelessWidget {
  const _TaskStepRow({required this.step});

  final TaskStep step;

  @override
  Widget build(BuildContext context) {
    final (color, statusLabel) = switch (step.status) {
      TaskStepStatus.pending => (KoraColors.textFaint, 'Pending'),
      TaskStepStatus.active => (KoraColors.primaryLight, 'In progress'),
      TaskStepStatus.done => (KoraColors.success, 'Done'),
    };

    return Semantics(
      label: '${step.label}, $statusLabel',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox.square(
            dimension: KoraSize.taskStatus,
            child: switch (step.status) {
              TaskStepStatus.pending => Icon(
                TablerIcons.circle,
                size: KoraSize.iconMd,
                color: color,
              ),
              TaskStepStatus.active => CircularProgressIndicator(
                strokeWidth: KoraSize.taskStatusStroke,
                color: color,
                backgroundColor: KoraColors.primaryTint,
              ),
              TaskStepStatus.done => Icon(
                TablerIcons.circleCheck,
                size: KoraSize.iconMd,
                color: color,
              ),
            },
          ),
          const SizedBox(width: KoraSpacing.md),
          Expanded(
            child: Text(
              step.label,
              style: KoraText.label.copyWith(
                color: step.status == TaskStepStatus.pending
                    ? KoraColors.textMuted
                    : KoraColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: KoraSpacing.sm),
          Text(statusLabel, style: KoraText.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}
