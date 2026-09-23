import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/summary/data/order_queue.dart';
import 'package:voiceops/features/summary/screens/summary_screen.dart';
import 'package:voiceops/providers/order_queue_provider.dart';
import 'package:voiceops/providers/queue_focus_provider.dart';
import 'package:voiceops/providers/shift_provider.dart';
import 'package:voiceops/providers/summary_stream_provider.dart';

import 'fake_voice.dart';
import 'order_queue_fixtures.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  late FakeKoraApi api;
  late ProviderContainer container;

  setUp(() => api = FakeKoraApi());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(KoraMotion.slow * 2);
  }

  Future<void> pump(WidgetTester tester, {bool shift = true}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(overrides: offlineOverrides(api: api));
    addTearDown(container.dispose);
    if (shift) await container.read(shiftProvider.notifier).ensureStarted();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildKoraTheme(),
          home: const Scaffold(body: SummaryScreen()),
        ),
      ),
    );
    await settle(tester);
  }

  void apply(OrderQueue queue) =>
      container.read(orderQueueProvider.notifier).apply(queue);

  Finder key(String value) => find.byKey(Key(value));

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
  }

  group('default state, before any report', () {
    testWidgets('no shift: still a useful overview', (tester) async {
      await pump(tester, shift: false);

      expect(find.text('Your shift summary'), findsOneWidget);
      expect(find.text('No shift yet'), findsOneWidget);
      expect(find.text('No orders yet'), findsOneWidget);
      for (final label in ['Completed', 'Active', 'Pending']) {
        expect(find.bySemanticsLabel('$label: 0'), findsOneWidget);
      }
      expect(key('summary-explainer'), findsOneWidget);
      expect(
        find.textContaining('generated as you complete orders'),
        findsOneWidget,
      );
      expect(find.text('No target set'), findsOneWidget);
      expect(key('queue-empty'), findsOneWidget);
      expect(api.reportRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a shift with no orders', (tester) async {
      await pump(tester);

      expect(find.text('Shift active'), findsOneWidget);
      expect(find.text('No orders yet'), findsOneWidget);
      expect(key('queue-empty'), findsOneWidget);
      expect(key('shift-progress-meter'), findsOneWidget);
      expect(api.reportRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a shift with orders but no report yet', (tester) async {
      api.queue = queueOf(5, completed: 2);
      await pump(tester);

      expect(find.text('Shift active'), findsOneWidget);
      expect(find.text('2 of 5 deliveries completed'), findsOneWidget);
      expect(find.bySemanticsLabel('Completed: 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Active: 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Pending: 2'), findsOneWidget);
      expect(key('summary-explainer'), findsOneWidget);
      expect(api.reportRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one order reads as a single delivery', (tester) async {
      api.queue = queueOf(1);
      await pump(tester);

      expect(find.text('0 of 1 delivery completed'), findsOneWidget);
    });

    testWidgets('failed and rescheduled orders are counted plainly', (
      tester,
    ) async {
      api.queue = OrderQueue.fromJson(
        queueJson([
          orderJson('a', 1, 'completed'),
          orderJson('b', 2, 'failed', name: 'Bola'),
          orderJson('c', 3, 'rescheduled', name: 'Chidi'),
          orderJson('d', 4, 'active'),
        ]),
      );
      await pump(tester);

      expect(find.text('1 failed · 1 rescheduled'), findsOneWidget);
      await scrollTo(tester, key('order-row-b'));
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Rescheduled'), findsOneWidget);
      expect(find.text('FAILED OR RESCHEDULED · 2'), findsOneWidget);
    });

    testWidgets('an event updates the screen with no refresh', (tester) async {
      api.queue = queueOf(5, completed: 2);
      await pump(tester);
      expect(find.text('2 of 5 deliveries completed'), findsOneWidget);

      apply(queueOf(5, completed: 3));
      await settle(tester);

      expect(find.text('3 of 5 deliveries completed'), findsOneWidget);
      expect(find.bySemanticsLabel('Completed: 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Pending: 1'), findsOneWidget);
    });

    testWidgets('the generated summary still shows below the overview', (
      tester,
    ) async {
      api.queue = queueOf(2, completed: 2);
      await pump(tester);
      container
          .read(summaryStreamProvider.notifier)
          .append('Two stops done.', isFinal: false);
      await settle(tester);

      expect(key('shift-overview'), findsOneWidget);
      await scrollTo(tester, find.text('Two stops done.'));
      expect(find.text('SHIFT SUMMARY - LIVE'), findsOneWidget);
    });
  });

  group('order queue', () {
    testWidgets('shows the active order, then pending, completed folded', (
      tester,
    ) async {
      api.queue = queueOf(5, completed: 1);
      await pump(tester);
      await scrollTo(tester, key('order-active'));

      expect(find.text('ACTIVE · STOP 2'), findsOneWidget);
      expect(
        find.descendant(
          of: key('order-active'),
          matching: find.text('Recipient 2'),
        ),
        findsOneWidget,
      );
      expect(find.text('2 Main Street'), findsOneWidget);
      expect(find.text('10:00 - 11:00'), findsOneWidget);
      expect(key('mark-completed'), findsOneWidget);

      await scrollTo(tester, find.text('UP NEXT · 3'));
      expect(key('order-row-d-3'), findsOneWidget);
      expect(find.text('4. Recipient 4'), findsOneWidget);

      // Completed orders start folded away.
      expect(key('order-row-d-1'), findsNothing);
      await scrollTo(tester, key('queue-completed-toggle'));
      await tester.tap(key('queue-completed-toggle'));
      await tester.pump();
      expect(key('order-row-d-1'), findsOneWidget);
      await tester.tap(key('queue-completed-toggle'));
      await tester.pump();
      expect(key('order-row-d-1'), findsNothing);
    });

    testWidgets('Mark completed sends delivered and the next order '
        'becomes active', (tester) async {
      api
        ..queue = queueOf(3)
        ..onDeliveryStatus = (id, status) =>
            api.queue = queueOf(3, completed: 1);
      await pump(tester);
      await scrollTo(tester, key('mark-completed'));

      await tester.tap(key('mark-completed'));
      await settle(tester);

      expect(api.deliveryStatusUpdates, [('d-1', 'delivered')]);
      expect(find.text('1 of 3 deliveries completed'), findsOneWidget);
      await scrollTo(tester, key('order-active'));
      expect(find.text('ACTIVE · STOP 2'), findsOneWidget);
    });

    testWidgets('a failed completion shows a calm error', (tester) async {
      api
        ..queue = queueOf(3)
        ..deliveryStatusFailure = const ApiException('Kora had a problem.');
      await pump(tester);
      await scrollTo(tester, key('mark-completed'));

      await tester.tap(key('mark-completed'));
      await settle(tester);

      await scrollTo(tester, key('queue-error'));
      expect(find.text('Kora had a problem.'), findsOneWidget);
      expect(find.text('0 of 3 deliveries completed'), findsOneWidget);
    });

    testWidgets('a finished queue has no active order', (tester) async {
      api.queue = queueOf(2, completed: 2);
      await pump(tester);

      expect(find.text('2 of 2 deliveries completed'), findsOneWidget);
      expect(key('order-active'), findsNothing);
      expect(key('mark-completed'), findsNothing);
      expect(key('queue-empty'), findsNothing);
    });

    testWidgets('refresh asks the backend again', (tester) async {
      api.queue = queueOf(2);
      await pump(tester);
      final before = api.queueRequests.length;

      api.queue = queueOf(3);
      await scrollTo(tester, key('queue-refresh'));
      await tester.tap(key('queue-refresh'));
      await settle(tester);

      expect(api.queueRequests.length, before + 1);
      expect(find.text('0 of 3 deliveries completed'), findsOneWidget);
    });

    testWidgets('a request from Home scrolls the queue into view', (
      tester,
    ) async {
      api.queue = queueOf(8);
      await pump(tester);
      final top = tester.getTopLeft(key('order-queue')).dy;
      expect(top, greaterThan(0));

      container.read(queueFocusRequestProvider.notifier).state = true;
      // One frame to see the request, one to run the scroll.
      await settle(tester);
      await settle(tester);

      expect(container.read(queueFocusRequestProvider), isFalse);
      expect(tester.getTopLeft(key('order-queue')).dy, lessThan(top));
    });
  });

  group('daily target', () {
    testWidgets('unset offers to set one, by touch or voice', (tester) async {
      await pump(tester);

      expect(find.text('No target set'), findsOneWidget);
      expect(find.textContaining('set my target to 15'), findsOneWidget);
      expect(key('target-progress-text'), findsNothing);
    });

    testWidgets('setting a target shows progress against it', (tester) async {
      api.queue = queueOf(20, completed: 8);
      await pump(tester);

      await scrollTo(tester, key('target-set'));
      await tester.tap(key('target-set'));
      await tester.pump();
      await tester.enterText(key('target-field'), '15');
      await scrollTo(tester, key('target-save'));
      // Scrolled flush to the top edge the button cannot be tapped.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 200),
      );
      await tester.pump();
      await tester.tap(key('target-save'));
      await settle(tester);

      expect(api.preferenceWrites, [(dailyDeliveryTargetKey, '15')]);
      expect(find.text('8 of 15 target deliveries completed'), findsOneWidget);
      expect(find.text('7 deliveries to go'), findsOneWidget);
      expect(key('target-field'), findsNothing);
    });

    testWidgets('only a positive whole number is accepted', (tester) async {
      await pump(tester);
      await scrollTo(tester, key('target-set'));
      await tester.tap(key('target-set'));
      await tester.pump();

      for (final bad in ['', '0']) {
        await tester.enterText(key('target-field'), bad);
        await tester.tap(key('target-save'));
        await tester.pump();
        expect(
          find.text('Enter a whole number from 1 to 500.'),
          findsOneWidget,
        );
      }
      // The field itself takes digits only, and no more than three.
      await tester.enterText(key('target-field'), '1.5-2');
      expect(
        tester.widget<TextField>(key('target-field')).controller!.text,
        '152',
      );
      await tester.enterText(key('target-field'), '501');
      await tester.tap(key('target-save'));
      await tester.pump();
      expect(find.text('Enter a whole number from 1 to 500.'), findsOneWidget);
      expect(api.preferenceWrites, isEmpty);

      await tester.tap(key('target-cancel'));
      await tester.pump();
      expect(find.text('No target set'), findsOneWidget);
    });

    testWidgets('a voice change arrives through the queue event', (
      tester,
    ) async {
      api.queue = queueOf(5, completed: 2);
      await pump(tester);
      expect(key('target-progress-text'), findsNothing);

      apply(queueOf(5, completed: 2, target: 15));
      await settle(tester);

      expect(find.text('2 of 15 target deliveries completed'), findsOneWidget);

      apply(queueOf(5, completed: 2));
      await settle(tester);
      expect(key('target-progress-text'), findsNothing);
    });

    testWidgets('one to go, then reached, then over: calm wording', (
      tester,
    ) async {
      api.queue = queueOf(5, completed: 2, target: 3);
      await pump(tester);
      expect(find.text('1 delivery to go'), findsOneWidget);

      apply(queueOf(5, completed: 3, target: 3));
      await settle(tester);
      expect(find.text('3 of 3 target deliveries completed'), findsOneWidget);
      expect(find.text('Target reached. Nice work today.'), findsOneWidget);

      apply(queueOf(5, completed: 5, target: 3));
      await settle(tester);
      expect(find.text('5 of 3 target deliveries completed'), findsOneWidget);
      expect(find.text('Target reached. Nice work today.'), findsOneWidget);
      expect(find.textContaining('to go'), findsNothing);
    });

    testWidgets('the target can be changed and cleared', (tester) async {
      api.queue = queueOf(5, completed: 1);
      api.preferences[dailyDeliveryTargetKey] = '4';
      await pump(tester);
      expect(find.text('1 of 4 target deliveries completed'), findsOneWidget);

      await scrollTo(tester, key('target-change'));
      await tester.tap(key('target-change'));
      await tester.pump();
      expect(
        tester.widget<TextField>(key('target-field')).controller!.text,
        '4',
      );
      await tester.enterText(key('target-field'), '6');
      await tester.tap(key('target-save'));
      await settle(tester);
      expect(find.text('1 of 6 target deliveries completed'), findsOneWidget);

      await tester.tap(key('target-clear'));
      await settle(tester);
      expect(api.preferences.containsKey(dailyDeliveryTargetKey), isFalse);
      expect(find.text('No target set'), findsOneWidget);
    });

    testWidgets('a failed save keeps the editor and says why', (tester) async {
      await pump(tester);
      api.preferencesFailure = const ApiException('Kora had a problem.');

      await scrollTo(tester, key('target-set'));
      await tester.tap(key('target-set'));
      await tester.pump();
      await tester.enterText(key('target-field'), '9');
      await tester.tap(key('target-save'));
      await settle(tester);

      expect(find.text('Kora had a problem.'), findsOneWidget);
      expect(key('target-field'), findsOneWidget);
    });
  });
}
