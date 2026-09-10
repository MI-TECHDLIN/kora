import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/task_progress_provider.dart';

class TaskProgressCard extends ConsumerWidget {
  const TaskProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(taskProgressProvider);
    final show = steps.isNotEmpty;

    return IgnorePointer(
      ignoring: !show,
      child: AnimatedSlide(
        offset: show ? Offset.zero : const Offset(0, 1.1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 140),
              child: Text('Task card placeholder — ${steps.length} steps'),
            ),
          ),
        ),
      ),
    );
  }
}
