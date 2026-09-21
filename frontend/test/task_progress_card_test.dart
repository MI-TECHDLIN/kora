import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/overlays/task_progress_card.dart';
import 'package:voiceops/providers/task_progress_provider.dart';
import 'package:voiceops/providers/voice_session_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  Future<({ProviderContainer container, FakeVoiceConnector connector})>
  pumpCard(WidgetTester tester) async {
    final connector = FakeVoiceConnector();
    final container = ProviderContainer(
      overrides: [
        ...signedInOverrides(),
        ...offlineOverrides(connector: connector),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Stack(children: [TaskProgressCard()])),
        ),
      ),
    );
    await container.read(voiceSessionProvider.notifier).onPushToTalk();
    await tester.pump();
    return (container: container, connector: connector);
  }

  Future<void> settleCard(WidgetTester tester) async {
    await tester.pump(); // Deliver the fake socket frame.
    await tester.pump(); // Rebuild and start the entrance animation.
    await tester.pump(KoraMotion.slow);
  }

  Future<void> closeCard(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await container.read(voiceSessionProvider.notifier).disconnect();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('renders parallel task steps and their contract statuses', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    final container = harness.container;

    harness.connector.last
      ..emit({
        'event': 'task_step',
        'step': 'Checking delivery route',
        'status': 'active',
      })
      ..emit({
        'event': 'task_step',
        'step': 'Texting the customer',
        'status': 'pending',
      });
    await settleCard(tester);

    expect(find.byKey(const Key('task-progress-card')), findsOneWidget);
    expect(find.text('Co-rider working'), findsOneWidget);
    expect(find.text('Checking delivery route'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Texting the customer'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('Why'), findsNothing);
    expect(
      tester
          .widget<GestureDetector>(find.byKey(const Key('task-progress-card')))
          .onTap,
      isNull,
    );

    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Checking delivery route',
      'status': 'done',
    });
    await tester.pump();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    await closeCard(tester, container);
  });

  testWidgets('shows trimmed reasoning and expands or collapses on tap', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Comparing routes',
      'status': 'active',
      'reasoning': '  The quieter route avoids roadworks near the next stop.  ',
    });
    await settleCard(tester);

    expect(find.text('Why'), findsOneWidget);
    final reasoning = tester.widget<Text>(
      find.byKey(const Key('task-reasoning')),
    );
    expect(
      reasoning.data,
      'The quieter route avoids roadworks near the next stop.',
    );
    expect(reasoning.maxLines, 1);

    await tester.tap(find.byKey(const Key('task-progress-card')));
    await tester.pump(KoraMotion.base);
    expect(
      tester.widget<Text>(find.byKey(const Key('task-reasoning'))).maxLines,
      isNull,
    );

    await tester.tap(find.byKey(const Key('task-progress-card')));
    await tester.pump(KoraMotion.base);
    expect(
      tester.widget<Text>(find.byKey(const Key('task-reasoning'))).maxLines,
      1,
    );
    await closeCard(tester, harness.container);
  });

  testWidgets('caps long reasoning at 140 characters', (tester) async {
    final harness = await pumpCard(tester);
    final longReasoning = List.filled(30, 'delivery').join(' ');
    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Checking constraints',
      'status': 'active',
      'reasoning': longReasoning,
    });
    await settleCard(tester);

    final stored = harness.container
        .read(taskProgressProvider)
        .single
        .reasoning!;
    expect(stored.runes.length, TaskStep.reasoningMaxLength);
    expect(stored, endsWith('…'));
    expect(
      tester.widget<Text>(find.byKey(const Key('task-reasoning'))).data,
      stored,
    );
    await closeCard(tester, harness.container);
  });

  testWidgets('keeps completed reasoning visible past the legacy hold', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Comparing routes',
      'status': 'done',
      'reasoning': 'The eastern route avoids a closure.',
    });
    await settleCard(tester);

    await tester.pump(KoraMotion.taskCompleteHold);
    expect(harness.container.read(taskProgressProvider), isNotEmpty);
    expect(find.text('Why'), findsOneWidget);
    await closeCard(tester, harness.container);
  });

  testWidgets('does not clear completed reasoning while it is expanded', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Comparing routes',
      'status': 'done',
      'reasoning': 'The eastern route avoids a closure.',
    });
    await settleCard(tester);
    await tester.tap(find.byKey(const Key('task-progress-card')));
    await tester.pump(KoraMotion.base);

    await tester.pump(KoraMotion.taskReasoningCompleteHold);
    expect(harness.container.read(taskProgressProvider), isNotEmpty);
    expect(
      tester.widget<Text>(find.byKey(const Key('task-reasoning'))).maxLines,
      isNull,
    );
    await closeCard(tester, harness.container);
  });

  testWidgets('starts a fresh reasoning hold when expansion is collapsed', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Comparing routes',
      'status': 'done',
      'reasoning': 'The eastern route avoids a closure.',
    });
    await settleCard(tester);
    await tester.tap(find.byKey(const Key('task-progress-card')));
    await tester.pump(KoraMotion.base);
    await tester.pump(KoraMotion.taskReasoningCompleteHold);

    await tester.tap(find.byKey(const Key('task-progress-card')));
    await tester.pump(KoraMotion.base);
    await tester.pump(const Duration(seconds: 7));
    expect(harness.container.read(taskProgressProvider), isNotEmpty);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(KoraMotion.slow);
    expect(harness.container.read(taskProgressProvider), isEmpty);
    await closeCard(tester, harness.container);
  });

  testWidgets('auto-collapses expanded reasoning after 30 seconds', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Comparing routes',
      'status': 'active',
      'reasoning': 'This route keeps the driver away from a closure.',
    });
    await settleCard(tester);
    await tester.tap(find.byKey(const Key('task-progress-card')));
    await tester.pump(KoraMotion.base);

    expect(
      tester.widget<Text>(find.byKey(const Key('task-reasoning'))).maxLines,
      isNull,
    );
    await tester.pump(KoraMotion.taskReasoningExpanded);
    await tester.pump(KoraMotion.base);
    expect(
      tester.widget<Text>(find.byKey(const Key('task-reasoning'))).maxLines,
      1,
    );
    await closeCard(tester, harness.container);
  });

  testWidgets('announces reasoning and expansion state to accessibility', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Comparing routes',
      'status': 'active',
      'reasoning': 'This route is eight minutes faster.',
    });
    await settleCard(tester);

    var semantics = tester.getSemantics(
      find.byKey(const Key('task-progress-semantics')),
    );
    expect(semantics.label, 'Working. 0 of 1 steps done.');
    expect(
      semantics.value,
      'Collapsed. Why: This route is eight minutes faster.',
    );

    await tester.tap(find.byKey(const Key('task-progress-card')));
    await tester.pump(KoraMotion.base);
    semantics = tester.getSemantics(
      find.byKey(const Key('task-progress-semantics')),
    );
    expect(
      semantics.value,
      'Expanded. Why: This route is eight minutes faster.',
    );
    await closeCard(tester, harness.container);
  });

  testWidgets('completion without reasoning still dismisses after 2 seconds', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    final container = harness.container;

    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Opening map',
      'status': 'done',
    });
    await settleCard(tester);

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
    await closeCard(tester, container);
  });
}
