import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/tokens.dart';

enum TaskStepStatus { pending, active, done }

class TaskStep {
  const TaskStep({
    required this.label,
    this.status = TaskStepStatus.pending,
    this.reasoning,
  });

  static const reasoningMaxLength = 140;
  static const reasoningExpansionHintLength = 100;

  final String label;
  final TaskStepStatus status;
  final String? reasoning;

  TaskStep copyWith({TaskStepStatus? status, String? reasoning}) => TaskStep(
    label: label,
    status: status ?? this.status,
    reasoning: reasoning ?? this.reasoning,
  );
}

/// Empty list = TaskProgressCard hidden. Driven by the voice session's
/// `task_step` events (docs/contracts/interface.md §1).
final taskProgressProvider =
    StateNotifierProvider<TaskProgressNotifier, List<TaskStep>>((ref) {
      return TaskProgressNotifier();
    });

class TaskProgressNotifier extends StateNotifier<List<TaskStep>> {
  TaskProgressNotifier() : super([]);

  Timer? _completionTimer;

  void setSteps(List<String> labels) {
    _completionTimer?.cancel();
    state = labels.map((l) => TaskStep(label: l)).toList();
    _scheduleClearIfComplete();
  }

  void clear() {
    _completionTimer?.cancel();
    state = [];
  }

  /// Keeps a completed task visible while the driver reads its reasoning.
  void pauseCompletionClear() => _completionTimer?.cancel();

  /// Starts a fresh completion hold after expanded reasoning is collapsed.
  void resumeCompletionClear() {
    _completionTimer?.cancel();
    _scheduleClearIfComplete();
  }

  /// Applies one `task_step` event. [label] identifies the step within the
  /// current task: a known step changes status, a new one is appended. A new
  /// step after every known step is done starts the next task.
  void applyStep(String label, TaskStepStatus status, {String? reasoning}) {
    _completionTimer?.cancel();
    final normalizedReasoning = _normalizeReasoning(reasoning);
    final finished =
        state.isNotEmpty && state.every((s) => s.status == TaskStepStatus.done);
    final index = state.indexWhere((s) => s.label == label);
    if (index == -1) {
      state = [
        if (!finished) ...state,
        TaskStep(label: label, status: status, reasoning: normalizedReasoning),
      ];
    } else {
      state = [
        for (var i = 0; i < state.length; i++)
          i == index
              ? state[i].copyWith(
                  status: status,
                  reasoning: normalizedReasoning,
                )
              : state[i],
      ];
    }
    _scheduleClearIfComplete();
  }

  String? _normalizeReasoning(String? reasoning) {
    final trimmed = reasoning?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final characters = trimmed.runes.toList();
    if (characters.length <= TaskStep.reasoningMaxLength) return trimmed;
    return '${String.fromCharCodes(characters.take(TaskStep.reasoningMaxLength - 1)).trimRight()}…';
  }

  void _scheduleClearIfComplete() {
    if (state.isEmpty || state.any((s) => s.status != TaskStepStatus.done)) {
      return;
    }
    final hold = state.any((step) => step.reasoning != null)
        ? KoraMotion.taskReasoningCompleteHold
        : KoraMotion.taskCompleteHold;
    _completionTimer = Timer(hold, () {
      if (mounted) state = [];
    });
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    super.dispose();
  }
}
