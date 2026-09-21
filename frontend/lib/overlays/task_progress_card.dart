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
  final _expandedSteps = <String>{};

  void _onExpansionChanged(String label, bool isExpanded) {
    if (isExpanded) {
      final wasEmpty = _expandedSteps.isEmpty;
      _expandedSteps.add(label);
      if (wasEmpty) {
        ref.read(taskProgressProvider.notifier).pauseCompletionClear();
      }
      return;
    }

    _expandedSteps.remove(label);
    if (_expandedSteps.isEmpty) {
      ref.read(taskProgressProvider.notifier).resumeCompletionClear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = ref.watch(taskProgressProvider);
    ref.listen(taskProgressProvider, (previous, next) {
      final expandableLabels = next
          .where(
            (step) =>
                step.status == TaskStepStatus.done && step.reasoning != null,
          )
          .map((step) => step.label)
          .toSet();
      _expandedSteps.removeWhere((label) => !expandableLabels.contains(label));
    });
    final show = steps.isNotEmpty;
    final complete = steps
        .where((step) => step.status == TaskStepStatus.done)
        .length;
    final allDone = show && complete == steps.length;

    return IgnorePointer(
      ignoring: !show,
      child: Semantics(
        key: const Key('task-progress-semantics'),
        container: show,
        explicitChildNodes: true,
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: KoraSize.touchTarget,
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
                            _TaskStepItem(
                              key: ValueKey(steps[index].label),
                              step: steps[index],
                              onExpansionChanged: _onExpansionChanged,
                            ),
                            if (index != steps.length - 1)
                              const SizedBox(height: KoraSpacing.md),
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
    );
  }
}

class _TaskStepItem extends StatelessWidget {
  const _TaskStepItem({
    super.key,
    required this.step,
    required this.onExpansionChanged,
  });

  final TaskStep step;
  final void Function(String label, bool isExpanded) onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final (color, statusLabel) = switch (step.status) {
      TaskStepStatus.pending => (KoraColors.textFaint, 'Pending'),
      TaskStepStatus.active => (KoraColors.primaryLight, 'In progress'),
      TaskStepStatus.done => (KoraColors.success, 'Done'),
    };
    final reasoning = step.reasoning;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          step.label,
          style: KoraText.weight(KoraText.title, FontWeight.w700).copyWith(
            color: step.status == TaskStepStatus.pending
                ? KoraColors.textMuted
                : KoraColors.textPrimary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (reasoning != null) ...[
          const SizedBox(height: KoraSpacing.xs),
          if (step.status == TaskStepStatus.active)
            _ActiveReasoning(
              key: ValueKey('active-reasoning-${step.label}'),
              label: step.label,
              reasoning: reasoning,
            )
          else if (step.status == TaskStepStatus.done)
            _DoneReasoning(
              key: ValueKey('done-reasoning-${step.label}'),
              label: step.label,
              reasoning: reasoning,
              onExpansionChanged: onExpansionChanged,
            ),
        ],
        const SizedBox(height: KoraSpacing.sm),
        Row(
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
            const SizedBox(width: KoraSpacing.sm),
            Text(statusLabel, style: KoraText.caption.copyWith(color: color)),
          ],
        ),
      ],
    );

    if (step.status == TaskStepStatus.done && reasoning != null) {
      return content;
    }

    return Semantics(
      label: [step.label, statusLabel, ?reasoning].join(', '),
      excludeSemantics: true,
      child: content,
    );
  }
}

class _ActiveReasoning extends StatefulWidget {
  const _ActiveReasoning({
    super.key,
    required this.label,
    required this.reasoning,
  });

  final String label;
  final String reasoning;

  @override
  State<_ActiveReasoning> createState() => _ActiveReasoningState();
}

class _ActiveReasoningState extends State<_ActiveReasoning> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      key: ValueKey('task-active-reasoning-fade-${widget.label}'),
      opacity: _visible ? 1 : 0,
      duration: KoraMotion.taskReasoningFadeIn,
      curve: KoraMotion.standard,
      child: Text(
        widget.reasoning,
        key: ValueKey('task-reasoning-${widget.label}'),
        style: KoraText.label.copyWith(
          color: KoraColors.taskReasoningActive,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _DoneReasoning extends StatefulWidget {
  const _DoneReasoning({
    super.key,
    required this.label,
    required this.reasoning,
    required this.onExpansionChanged,
  });

  final String label;
  final String reasoning;
  final void Function(String label, bool isExpanded) onExpansionChanged;

  @override
  State<_DoneReasoning> createState() => _DoneReasoningState();
}

class _DoneReasoningState extends State<_DoneReasoning> {
  bool _isExpanded = false;
  Timer? _collapseTimer;

  bool get _isLong =>
      widget.reasoning.runes.length > TaskStep.reasoningExpansionHintLength;

  void _toggleExpanded() {
    _collapseTimer?.cancel();
    final willExpand = !_isExpanded;
    setState(() => _isExpanded = willExpand);
    widget.onExpansionChanged(widget.label, willExpand);
    if (willExpand) {
      _collapseTimer = Timer(KoraMotion.taskReasoningExpanded, () {
        if (!mounted) return;
        setState(() => _isExpanded = false);
        widget.onExpansionChanged(widget.label, false);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _DoneReasoning oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isExpanded && oldWidget.reasoning != widget.reasoning) {
      _collapseTimer?.cancel();
      _isExpanded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpansionChanged(widget.label, false);
      });
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '${widget.label}, Done, ${widget.reasoning}',
      value: _isExpanded ? 'Expanded' : 'Collapsed',
      onTap: _toggleExpanded,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: ValueKey('task-reasoning-toggle-${widget.label}'),
          behavior: HitTestBehavior.opaque,
          onTap: _toggleExpanded,
          child: AnimatedSize(
            duration: KoraMotion.taskReasoningResize,
            curve: KoraMotion.standard,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isExpanded)
                  ConstrainedBox(
                    key: ValueKey('task-reasoning-expanded-${widget.label}'),
                    constraints: const BoxConstraints(
                      maxHeight: KoraSize.taskReasoningExpandedMaxHeight,
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        widget.reasoning,
                        key: ValueKey('task-reasoning-${widget.label}'),
                        style: KoraText.body.copyWith(
                          color: KoraColors.taskReasoningDone,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    widget.reasoning,
                    key: ValueKey('task-reasoning-${widget.label}'),
                    style: KoraText.body.copyWith(
                      color: KoraColors.taskReasoningDone,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (_isLong && !_isExpanded) ...[
                  const SizedBox(height: KoraSpacing.xs),
                  Text(
                    'Tap to expand',
                    key: ValueKey('task-reasoning-hint-${widget.label}'),
                    style: KoraText.caption.copyWith(
                      color: KoraColors.primaryLight,
                    ),
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
