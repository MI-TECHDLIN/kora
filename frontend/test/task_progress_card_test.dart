import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/overlays/task_progress_card.dart';
import 'package:voiceops/providers/task_progress_provider.dart';

import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('renders parallel task steps and their contract statuses', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Stack(children: [TaskProgressCard()])),
        ),
      ),
    );

    final tasks = container.read(taskProgressProvider.notifier)
      ..applyStep('Checking delivery route', TaskStepStatus.active)
      ..applyStep('Texting the customer', TaskStepStatus.pending);
    await tester.pump(KoraMotion.slow);

    expect(find.byKey(const Key('task-progress-card')), findsOneWidget);
    expect(find.text('Co-rider working'), findsOneWidget);
    expect(find.text('Checking delivery route'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Texting the customer'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);

    tasks.applyStep('Checking delivery route', TaskStepStatus.done);
    await tester.pump();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('confirms completion, then dismisses the card', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Stack(children: [TaskProgressCard()])),
        ),
      ),
    );

    container
        .read(taskProgressProvider.notifier)
        .applyStep('Opening map', TaskStepStatus.done);
    await tester.pump(KoraMotion.slow);

    expect(find.text('Task complete'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);

    await tester.pump(KoraMotion.taskCompleteHold);
    await tester.pump(KoraMotion.slow);

    expect(container.read(taskProgressProvider), isEmpty);
    expect(find.text('Task complete'), findsNothing);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
  });
}
