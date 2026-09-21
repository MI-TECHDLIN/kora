import 'dart:async';

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
class TaskProgressCard extends ConsumerStatefulWidget {
  const TaskProgressCard({super.key});

  @override
  ConsumerState<TaskProgressCard> createState() => _TaskProgressCardState();
}

class _TaskProgressCardState extends ConsumerState<TaskProgressCard> {
  bool _isExpanded = false;
  Timer? _collapseTimer;

  String? _latestReasoning(List<TaskStep> steps) {
    for (final step in steps.reversed) {
      if (step.reasoning != null) return step.reasoning;
    }
    return null;
  }

  void _toggleExpanded() {
    _collapseTimer?.cancel();
    final willExpand = !_isExpanded;
    setState(() => _isExpanded = willExpand);
    if (willExpand) {
      ref.read(taskProgressProvider.notifier).pauseCompletionClear();
      _collapseTimer = Timer(KoraMotion.taskReasoningExpanded, () {
        if (!mounted) return;
        setState(() => _isExpanded = false);
        ref.read(taskProgressProvider.notifier).resumeCompletionClear();
      });
    } else {
      ref.read(taskProgressProvider.notifier).resumeCompletionClear();
    }
  }

  void _collapse() {
    _collapseTimer?.cancel();
    if (_isExpanded) {
      setState(() => _isExpanded = false);
      ref.read(taskProgressProvider.notifier).resumeCompletionClear();
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = ref.watch(taskProgressProvider);
    ref.listen(taskProgressProvider, (previous, next) {
      if (_latestReasoning(previous ?? const <TaskStep>[]) !=
          _latestReasoning(next)) {
        _collapse();
      }
    });
    final show = steps.isNotEmpty;
    final reasoning = _latestReasoning(steps);
    final complete = steps
        .where((step) => step.status == TaskStepStatus.done)
        .length;
    final allDone = show && complete == steps.length;

    return IgnorePointer(
      ignoring: !show || reasoning == null,
      child: Semantics(
        key: const Key('task-progress-semantics'),
        container: show,
        explicitChildNodes: true,
        liveRegion: show,
        button: reasoning != null,
        onTap: reasoning == null ? null : _toggleExpanded,
        label: show
            ? allDone
                  ? 'Task complete. $complete of ${steps.length} steps done.'
                  : 'Working. $complete of ${steps.length} steps done.'
            : null,
        value: reasoning == null
            ? null
            : '${_isExpanded ? 'Expanded' : 'Collapsed'}. Why: $reasoning',
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
                  child: GestureDetector(
                    key: const Key('task-progress-card'),
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: reasoning == null ? null : _toggleExpanded,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: KoraSize.touchTarget,
                      ),
                      child: GlassCard(
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
                                    allDone
                                        ? 'Task complete'
                                        : 'Co-rider working',
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
                            for (
                              var index = 0;
                              index < steps.length;
                              index++
                            ) ...[
                              _TaskStepRow(step: steps[index]),
                              if (index != steps.length - 1)
                                const SizedBox(height: KoraSpacing.sm),
                            ],
                            if (reasoning != null) ...[
                              const SizedBox(height: KoraSpacing.md),
                              AnimatedSize(
                                duration: KoraMotion.base,
                                curve: KoraMotion.standard,
                                alignment: Alignment.topCenter,
                                child: _ReasoningLine(
                                  reasoning: reasoning,
                                  isExpanded: _isExpanded,
                                ),
                              ),
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
        ),
      ),
    );
  }
}

class _ReasoningLine extends StatelessWidget {
  const _ReasoningLine({required this.reasoning, required this.isExpanded});

  final String reasoning;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          TablerIcons.bulb,
          size: KoraSize.iconSm,
          color: KoraColors.primaryLight,
        ),
        const SizedBox(width: KoraSpacing.sm),
        Text(
          'Why',
          style: KoraText.caption.copyWith(color: KoraColors.primaryLight),
        ),
        const SizedBox(width: KoraSpacing.sm),
        Expanded(
          child: Text(
            reasoning,
            key: const Key('task-reasoning'),
            style: KoraText.bodyMuted,
            maxLines: isExpanded ? null : 1,
            overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
      ],
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
