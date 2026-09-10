import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TaskStepStatus { pending, active, done }

class TaskStep {
  const TaskStep({required this.label, this.status = TaskStepStatus.pending});
  final String label;
  final TaskStepStatus status;
  TaskStep copyWith({TaskStepStatus? status}) =>
      TaskStep(label: label, status: status ?? this.status);
}

/// Empty list = TaskProgressCard hidden. Populated by FastAPI "task_step"
/// events in Checkpoint 2.
final taskProgressProvider =
    StateNotifierProvider<TaskProgressNotifier, List<TaskStep>>((ref) {
      return TaskProgressNotifier();
    });

class TaskProgressNotifier extends StateNotifier<List<TaskStep>> {
  TaskProgressNotifier() : super([]);
  void setSteps(List<String> labels) =>
      state = labels.map((l) => TaskStep(label: l)).toList();
  void clear() => state = [];
}
