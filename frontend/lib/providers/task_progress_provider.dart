import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  void setSteps(List<String> labels) =>
      state = labels.map((l) => TaskStep(label: l)).toList();
  void clear() => state = [];

  /// Applies one `task_step` event. [label] identifies the step within the
  /// current task: a known step changes status, a new one is appended. A new
  /// step after every known step is done starts the next task.
  void applyStep(String label, TaskStepStatus status) {
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
  }
}
