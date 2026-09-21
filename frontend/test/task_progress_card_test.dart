import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/realtime/voice_events.dart';
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

  test('task_step parsing carries optional reasoning', () {
    final withReasoning = VoiceEvent.parse({
      'event': 'task_step',
      'step': 'Checking delivery route',
      'status': 'active',
      'reasoning': 'Checking traffic and calculating the fastest route.',
    });
    final withoutReasoning = VoiceEvent.parse({
      'event': 'task_step',
      'step': 'Texting the customer',
      'status': 'done',
    });

    expect(
      withReasoning,
      isA<TaskStepEvent>().having(
        (event) => event.reasoning,
        'reasoning',
        'Checking traffic and calculating the fastest route.',
      ),
    );
    expect(
      withoutReasoning,
      isA<TaskStepEvent>().having(
        (event) => event.reasoning,
        'reasoning',
        isNull,
      ),
    );
  });

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
    expect(
      find.byKey(const Key('task-reasoning-Checking delivery route')),
      findsNothing,
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

  testWidgets('parallel reasoning stays per step and updates live by status', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    harness.connector.last
      ..emit({
        'event': 'task_step',
        'step': 'Checking delivery route',
        'status': 'active',
        'reasoning': 'Checking traffic and calculating the fastest route.',
      })
      ..emit({
        'event': 'task_step',
        'step': 'Texting the customer',
        'status': 'active',
        'reasoning': 'Preparing an arrival update for the customer.',
      });
    await settleCard(tester);

    final routeActive = tester.widget<Text>(
      find.byKey(const Key('task-reasoning-Checking delivery route')),
    );
    final messageActive = tester.widget<Text>(
      find.byKey(const Key('task-reasoning-Texting the customer')),
    );
    expect(
      routeActive.data,
      'Checking traffic and calculating the fastest route.',
    );
    expect(messageActive.data, 'Preparing an arrival update for the customer.');
    expect(routeActive.style?.fontStyle, FontStyle.italic);
    expect(routeActive.style?.color, KoraColors.taskReasoningActive);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(
              const Key('task-active-reasoning-fade-Checking delivery route'),
            ),
          )
          .duration,
      KoraMotion.taskReasoningFadeIn,
    );

    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Checking delivery route',
      'status': 'done',
      'reasoning': 'This route saves about 7 min versus the alternative.',
    });
    await tester.pump();

    final routeDone = tester.widget<Text>(
      find.byKey(const Key('task-reasoning-Checking delivery route')),
    );
    expect(
      routeDone.data,
      'This route saves about 7 min versus the alternative.',
    );
    expect(routeDone.maxLines, 2);
    expect(routeDone.style?.fontStyle, isNot(FontStyle.italic));
    expect(routeDone.style?.color, KoraColors.taskReasoningDone);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('task-reasoning-Texting the customer')),
          )
          .data,
      'Preparing an arrival update for the customer.',
    );
    await closeCard(tester, harness.container);
  });

  testWidgets('missing and empty reasoning render no explanation', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    harness.connector.last
      ..emit({'event': 'task_step', 'step': 'Opening map', 'status': 'active'})
      ..emit({
        'event': 'task_step',
        'step': 'Loading route',
        'status': 'active',
        'reasoning': '   ',
      });
    await settleCard(tester);

    expect(find.byKey(const Key('task-reasoning-Opening map')), findsNothing);
    expect(find.byKey(const Key('task-reasoning-Loading route')), findsNothing);
    expect(
      harness.container
          .read(taskProgressProvider)
          .every((step) => step.reasoning == null),
      isTrue,
    );
    await closeCard(tester, harness.container);
  });

  testWidgets('done reasoning expands and collapses independently on tap', (
    tester,
  ) async {
    final harness = await pumpCard(tester);
    final result = List.filled(
      14,
      'The quieter route avoids roadworks near the next stop.',
    ).join(' ');
    harness.connector.last.emit({
      'event': 'task_step',
      'step': 'Comparing routes',
      'status': 'done',
      'reasoning': '  $result  ',
    });
    await settleCard(tester);

    final stored = harness.container
        .read(taskProgressProvider)
        .single
        .reasoning!;
    final reasoning = tester.widget<Text>(
      find.byKey(const Key('task-reasoning-Comparing routes')),
    );
    expect(reasoning.data, stored);
    expect(reasoning.maxLines, 2);
    expect(reasoning.overflow, TextOverflow.ellipsis);
    expect(find.text('Tap to expand'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('task-reasoning-toggle-Comparing routes')),
    );
    await tester.pump(KoraMotion.taskReasoningResize);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('task-reasoning-Comparing routes')),
          )
          .maxLines,
      isNull,
    );
    expect(
      tester
          .widget<ConstrainedBox>(
            find.byKey(const Key('task-reasoning-expanded-Comparing routes')),
          )
          .constraints
          .maxHeight,
      KoraSize.taskReasoningExpandedMaxHeight,
    );
    expect(find.text('Tap to expand'), findsNothing);

    await tester.tap(
      find.byKey(const Key('task-reasoning-toggle-Comparing routes')),
    );
    await tester.pump(KoraMotion.taskReasoningResize);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('task-reasoning-Comparing routes')),
          )
          .maxLines,
      2,
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
      tester
          .widget<Text>(
            find.byKey(const Key('task-reasoning-Checking constraints')),
          )
          .data,
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
    expect(find.text('The eastern route avoids a closure.'), findsOneWidget);
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
    await tester.tap(
      find.byKey(const Key('task-reasoning-toggle-Comparing routes')),
    );
    await tester.pump(KoraMotion.taskReasoningResize);

    await tester.pump(KoraMotion.taskReasoningCompleteHold);
    expect(harness.container.read(taskProgressProvider), isNotEmpty);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('task-reasoning-Comparing routes')),
          )
          .maxLines,
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
    await tester.tap(
      find.byKey(const Key('task-reasoning-toggle-Comparing routes')),
    );
    await tester.pump(KoraMotion.taskReasoningResize);
    await tester.pump(KoraMotion.taskReasoningCompleteHold);

    await tester.tap(
      find.byKey(const Key('task-reasoning-toggle-Comparing routes')),
    );
    await tester.pump(KoraMotion.taskReasoningResize);
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
      'status': 'done',
      'reasoning': 'This route keeps the driver away from a closure.',
    });
    await settleCard(tester);
    await tester.tap(
      find.byKey(const Key('task-reasoning-toggle-Comparing routes')),
    );
    await tester.pump(KoraMotion.taskReasoningResize);

    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('task-reasoning-Comparing routes')),
          )
          .maxLines,
      isNull,
    );
    await tester.pump(KoraMotion.taskReasoningExpanded);
    await tester.pump(KoraMotion.taskReasoningResize);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('task-reasoning-Comparing routes')),
          )
          .maxLines,
      2,
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
      'status': 'done',
      'reasoning': 'This route is eight minutes faster.',
    });
    await settleCard(tester);

    final cardSemantics = tester.getSemantics(
      find.byKey(const Key('task-progress-semantics')),
    );
    expect(cardSemantics.label, 'Task complete. 1 of 1 steps done.');
    var semantics = tester.getSemantics(
      find.byKey(const Key('task-reasoning-toggle-Comparing routes')),
    );
    expect(
      semantics.label,
      'Comparing routes, Done, This route is eight minutes faster.',
    );
    expect(semantics.value, 'Collapsed');

    await tester.tap(
      find.byKey(const Key('task-reasoning-toggle-Comparing routes')),
    );
    await tester.pump(KoraMotion.taskReasoningResize);
    semantics = tester.getSemantics(
      find.byKey(const Key('task-reasoning-toggle-Comparing routes')),
    );
    expect(semantics.value, 'Expanded');
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
