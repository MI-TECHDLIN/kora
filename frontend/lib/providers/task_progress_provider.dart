import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/tokens.dart';

enum TaskStepStatus { pending, active, done }

class TaskStep {
  const TaskStep({required this.label, this.status = TaskStepStatus.pending});
  final String label;
  final TaskStepStatus status;
  TaskStep copyWith({TaskStepStatus? status}) =>
      TaskStep(label: label, status: status ?? this.status);
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

  /// Applies one `task_step` event. [label] identifies the step within the
  /// current task: a known step changes status, a new one is appended. A new
  /// step after every known step is done starts the next task.
  void applyStep(String label, TaskStepStatus status) {
    _completionTimer?.cancel();
    final finished =
        state.isNotEmpty && state.every((s) => s.status == TaskStepStatus.done);
    final index = state.indexWhere((s) => s.label == label);
    if (index == -1) {
      state = [if (!finished) ...state, TaskStep(label: label, status: status)];
    } else {
      state = [
        for (var i = 0; i < state.length; i++)
          i == index ? state[i].copyWith(status: status) : state[i],
      ];
    }
    _scheduleClearIfComplete();
  }

  void _scheduleClearIfComplete() {
    if (state.isEmpty || state.any((s) => s.status != TaskStepStatus.done)) {
      return;
    }
    _completionTimer = Timer(KoraMotion.taskCompleteHold, () {
      if (mounted) state = [];
    });
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    super.dispose();
  }
}
