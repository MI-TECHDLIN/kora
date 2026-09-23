import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/realtime/voice_events.dart';
import 'package:voiceops/features/summary/data/order_queue.dart';
import 'package:voiceops/providers/order_queue_provider.dart';
import 'package:voiceops/providers/shift_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'order_queue_fixtures.dart';

void main() {
  group('OrderQueue', () {
    test('parses a snapshot: states, counts, target and order', () {
      final queue = OrderQueue.fromJson(
        queueJson([
          orderJson('a', 1, 'completed'),
          orderJson('b', 2, 'active', window: '9:00 - 10:00', eta: 7),
          orderJson('c', 3, 'pending'),
          orderJson('d', 4, 'failed'),
          orderJson('e', 5, 'rescheduled'),
        ], target: 15),
      );

      expect(queue.shiftId, 'shift-1');
      expect(queue.target, 15);
      expect(queue.orders.map((o) => o.deliveryId), ['a', 'b', 'c', 'd', 'e']);
      expect(queue.counts.total, 5);
      expect(queue.counts.completed, 1);
      expect(queue.counts.failed, 1);
      expect(queue.counts.rescheduled, 1);
      expect(queue.active?.deliveryId, 'b');
      expect(queue.active?.timeWindow, '9:00 - 10:00');
      expect(queue.active?.etaMinutes, 7);
      expect(queue.ordersIn(OrderState.pending).single.deliveryId, 'c');
    });

    test('an empty shift is empty, with no target', () {
      final queue = OrderQueue.fromJson(queueJson(const []));
      expect(queue.isEmpty, isTrue);
      expect(queue.active, isNull);
      expect(queue.target, isNull);
      expect(queue.shiftFraction, 0);
      expect(queue.upNext(4), isEmpty);
    });

    test('reads the raw status when a snapshot has no state, and derives '
        'counts when they are missing', () {
      final queue = OrderQueue.fromJson({
        'shift_id': 's',
        'orders': [
          {'delivery_id': 'a', 'sequence': 1, 'status': 'delivered'},
          {'delivery_id': 'b', 'sequence': 2, 'status': 'pending'},
          {'delivery_id': 'c', 'sequence': 3, 'state': 'from-the-future'},
        ],
      });
      expect(queue.orders.map((o) => o.state), [
        OrderState.completed,
        OrderState.pending,
        OrderState.pending,
      ]);
      expect(queue.counts.total, 3);
      expect(queue.counts.completed, 1);
      expect(queue.counts.pending, 2);
    });

    test('keeps the backend order, and numbers a stop with no sequence', () {
      final queue = OrderQueue.fromJson(
        queueJson([
          {...orderJson('a', 1, 'active'), 'sequence': 1},
          {...orderJson('b', 2, 'pending'), 'sequence': 4},
          {...orderJson('c', 3, 'pending'), 'sequence': null},
        ]),
      );
      expect(queue.orders.map((o) => o.deliveryId), ['a', 'b', 'c']);
      expect(queue.orders.map((o) => o.sequence), [1, 4, 3]);
    });

    test('upNext is the active order then pending, up to the limit', () {
      final queue = queueOf(7, completed: 2);
      expect(queue.upNext(4).map((o) => o.deliveryId), [
        'd-3',
        'd-4',
        'd-5',
        'd-6',
      ]);
    });

    group('progress maths', () {
      test('shift progress is completed over total', () {
        final queue = queueOf(5, completed: 2);
        expect(queue.completed, 2);
        expect(queue.shiftFraction, closeTo(0.4, 1e-9));
        expect(queue.hasTarget, isFalse);
        expect(queue.targetRemaining, 0);
        expect(queue.targetReached, isFalse);
      });

      test('a target below the total counts remaining deliveries', () {
        final queue = queueOf(20, completed: 8, target: 15);
        expect(queue.targetFraction, closeTo(8 / 15, 1e-9));
        expect(queue.targetRemaining, 7);
        expect(queue.targetReached, isFalse);
      });

      test('reaching the target is reached with nothing remaining', () {
        final queue = queueOf(5, completed: 3, target: 3);
        expect(queue.targetFraction, 1);
        expect(queue.targetRemaining, 0);
        expect(queue.targetReached, isTrue);
      });

      test('going over the target clamps the bar and stays reached', () {
        final queue = queueOf(5, completed: 5, target: 3);
        expect(queue.targetFraction, 1);
        expect(queue.targetRemaining, 0);
        expect(queue.targetReached, isTrue);
      });

      test('a zero or negative target is no target', () {
        for (final raw in [0, -4, 'abc', null]) {
          final queue = OrderQueue.fromJson({
            ...queueJson([orderJson('a', 1, 'completed')]),
            'target': raw,
          });
          expect(queue.target, isNull, reason: '$raw');
          expect(queue.hasTarget, isFalse);
          expect(queue.targetFraction, 0);
          expect(queue.targetReached, isFalse);
        }
      });

      test('a stored string target reads as a number', () {
        final queue = OrderQueue.fromJson({
          ...queueJson(const []),
          'target': '15',
        });
        expect(queue.target, 15);
        expect(queue.targetFraction, 0);
        expect(queue.targetRemaining, 15);
      });
    });

    test('parseTarget accepts a positive whole number only', () {
      expect(parseTarget('15'), 15);
      expect(parseTarget(' 8 '), 8);
      expect(parseTarget('500'), 500);
      for (final bad in ['', '0', '-3', '2.5', 'abc', '1e3', '501']) {
        expect(parseTarget(bad), isNull, reason: bad);
      }
    });
  });

  test('VoiceEvent.parse reads queue_updated as a snapshot', () {
    final event = VoiceEvent.parse({
      'event': 'queue_updated',
      ...queueJson([
        orderJson('a', 1, 'active'),
        orderJson('b', 2, 'pending'),
      ], target: 4),
    });
    expect(event, isA<QueueUpdatedEvent>());
    final queue = (event as QueueUpdatedEvent).queue;
    expect(queue.target, 4);
    expect(queue.active?.deliveryId, 'a');
  });

  group('HttpKoraApi', () {
    late http.Request seen;

    HttpKoraApi api(http.Response Function(http.Request) respond) =>
        HttpKoraApi(
          baseUri: Uri.parse('https://api.voiceops.test'),
          auth: FakeAuthRepository(signedIn: true),
          client: MockClient((request) async {
            seen = request;
            return respond(request);
          }),
        );

    test('fetchOrderQueue GETs the shift queue', () async {
      final queue = await api(
        (_) => http.Response(
          jsonEncode(queueJson([orderJson('a', 1, 'active')], target: 6)),
          200,
        ),
      ).fetchOrderQueue('shift-1');

      expect(seen.method, 'GET');
      expect(seen.url.path, '/v1/shift/shift-1/queue');
      expect(seen.headers['Authorization'], 'Bearer test-access-token');
      expect(queue.target, 6);
      expect(queue.active?.deliveryId, 'a');
    });

    test('a backend without the endpoint is an ApiException', () {
      expect(
        api(
          (_) => http.Response('{"detail":"Not Found"}', 404),
        ).fetchOrderQueue('shift-1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('updateDeliveryStatus PUTs the frozen status value', () async {
      await api(
        (_) => http.Response('{}', 200),
      ).updateDeliveryStatus('d 1', 'delivered');

      expect(seen.method, 'PUT');
      expect(seen.url.path, '/v1/deliveries/d%201/status');
      expect(jsonDecode(seen.body), {'status': 'delivered'});
    });
  });

  group('orderQueueProvider', () {
    late FakeKoraApi api;
    late ProviderContainer container;

    setUp(() {
      api = FakeKoraApi();
      container = ProviderContainer(
        overrides: [koraApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
    });

    OrderQueue queue() => container.read(orderQueueProvider).queue;
    OrderQueueNotifier notifier() =>
        container.read(orderQueueProvider.notifier);

    test('starts empty', () async {
      container.read(orderQueueProvider);
      await pumpEventQueue();
      expect(queue().isEmpty, isTrue);
      expect(queue().target, isNull);
    });

    test('with no shift it only reads the saved target', () async {
      api.preferences[dailyDeliveryTargetKey] = '12';
      container.read(orderQueueProvider);
      await pumpEventQueue();

      expect(queue().target, 12);
      expect(api.queueRequests, isEmpty);
    });

    test('starting a shift seeds the queue from the REST snapshot', () async {
      api.queue = queueOf(5, completed: 2, target: 15);
      await container.read(shiftProvider.notifier).ensureStarted();
      await pumpEventQueue();

      expect(api.queueRequests, ['shift-1']);
      expect(queue().counts.total, 5);
      expect(queue().completed, 2);
      expect(queue().target, 15);
      expect(container.read(orderQueueProvider).loading, isFalse);
    });

    test('an event snapshot replaces the current one', () async {
      api.queue = queueOf(5, completed: 2);
      await container.read(shiftProvider.notifier).ensureStarted();
      await pumpEventQueue();

      notifier().apply(queueOf(5, completed: 3, target: 8));

      expect(queue().completed, 3);
      expect(queue().target, 8);
      expect(queue().active?.deliveryId, 'd-4');
    });

    test('an event for another shift is ignored', () async {
      api.queue = queueOf(2);
      await container.read(shiftProvider.notifier).ensureStarted();
      await pumpEventQueue();

      notifier().apply(
        OrderQueue.fromJson(queueJson(const [], shiftId: 'shift-other')),
      );

      expect(queue().counts.total, 2);
    });

    test('a new shift clears the old queue before its own arrives', () async {
      api.queue = queueOf(5, completed: 2, target: 9);
      final shifts = container.read(shiftProvider.notifier);
      await shifts.ensureStarted();
      await pumpEventQueue();
      expect(queue().counts.total, 5);

      shifts.clear();
      expect(queue().isEmpty, isTrue);
      expect(queue().target, isNull);

      api.queue = queueOf(1);
      await shifts.ensureStarted();
      await pumpEventQueue();
      expect(queue().counts.total, 1);
      expect(queue().target, isNull);
    });

    test('a fetch that lands after a reset is dropped', () async {
      api.queue = queueOf(3);
      final shifts = container.read(shiftProvider.notifier);
      await shifts.ensureStarted();
      // The refresh is in flight; the driver signs out before it lands.
      shifts.clear();
      await pumpEventQueue();

      expect(queue().isEmpty, isTrue);
    });

    test('a backend without a queue keeps the empty state', () async {
      api.queueFailure = const ApiException('nope', statusCode: 404);
      await container.read(shiftProvider.notifier).ensureStarted();
      await pumpEventQueue();

      expect(queue().isEmpty, isTrue);
      expect(container.read(orderQueueProvider).loading, isFalse);
      expect(container.read(orderQueueProvider).error, isNull);
    });

    test(
      'completing an order sends delivered, then the next is active',
      () async {
        api
          ..queue = queueOf(3)
          ..onDeliveryStatus = (id, status) =>
              api.queue = queueOf(3, completed: 1);
        await container.read(shiftProvider.notifier).ensureStarted();
        await pumpEventQueue();
        expect(queue().active?.deliveryId, 'd-1');

        expect(await notifier().complete('d-1'), isTrue);

        expect(api.deliveryStatusUpdates, [('d-1', 'delivered')]);
        expect(queue().completed, 1);
        expect(queue().active?.deliveryId, 'd-2');
        expect(container.read(orderQueueProvider).busyDeliveryId, isNull);
      },
    );

    test('a failed completion says so and changes nothing', () async {
      api
        ..queue = queueOf(3)
        ..deliveryStatusFailure = const ApiException('Kora had a problem.');
      await container.read(shiftProvider.notifier).ensureStarted();
      await pumpEventQueue();

      expect(await notifier().complete('d-1'), isFalse);

      final state = container.read(orderQueueProvider);
      expect(state.error, 'Kora had a problem.');
      expect(state.busyDeliveryId, isNull);
      expect(state.queue.completed, 0);
    });

    test('setting the target writes the shared preference', () async {
      api.queue = queueOf(3);
      await container.read(shiftProvider.notifier).ensureStarted();
      await pumpEventQueue();

      expect(await notifier().setTarget(15), isTrue);
      expect(api.preferenceWrites, [(dailyDeliveryTargetKey, '15')]);
      expect(queue().target, 15);

      expect(await notifier().setTarget(null), isTrue);
      expect(api.preferences.containsKey(dailyDeliveryTargetKey), isFalse);
      expect(queue().target, isNull);
    });

    test('a target that fails to save is reported, not shown', () async {
      api.preferencesFailure = const ApiException('offline');
      await pumpEventQueue();

      expect(await notifier().setTarget(15), isFalse);
      expect(container.read(orderQueueProvider).targetError, 'offline');
      expect(queue().target, isNull);
    });
  });
}
