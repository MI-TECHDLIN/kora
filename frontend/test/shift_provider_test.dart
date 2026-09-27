import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/providers/shift_provider.dart';
import 'package:voiceops/providers/summary_stream_provider.dart';

import 'fake_voice.dart';

void main() {
  group('shiftProvider / summaryStreamProvider', () {
    late FakeKoraApi api;
    late ProviderContainer container;

    setUp(() {
      api = FakeKoraApi();
      container = ProviderContainer(
        overrides: [koraApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
    });

    test('starting a shift resets a previous shift\'s streamed summary', () async {
      await container.read(shiftProvider.notifier).ensureStarted();
      container
          .read(summaryStreamProvider.notifier)
          .append('You did great today.', isFinal: true);
      expect(container.read(summaryStreamProvider)?.text, 'You did great today.');

      // Driver signs out (or the app otherwise forgets the shift) ...
      container.read(shiftProvider.notifier).clear();
      // ... and starts a new one.
      await container.read(shiftProvider.notifier).ensureStarted();

      expect(container.read(summaryStreamProvider), isNull);
    });

    test('a shift that is still active is not restarted, so summary stays', () async {
      await container.read(shiftProvider.notifier).ensureStarted();
      container
          .read(summaryStreamProvider.notifier)
          .append('Mid-shift check-in.', isFinal: true);

      // ensureStarted() called again mid-shift (e.g. a second driver turn)
      // must not treat this as a new shift.
      await container.read(shiftProvider.notifier).ensureStarted();

      expect(api.shiftCalls, 1);
      expect(container.read(summaryStreamProvider)?.text, 'Mid-shift check-in.');
    });

    test(
      'markEnded forces the next ensureStarted to start a fresh shift '
      '(the "orders stopped" bug: a reconnect must not reuse a dead shift_id)',
      () async {
        await container.read(shiftProvider.notifier).ensureStarted();
        expect(api.shiftCalls, 1);

        // The backend told us this shift ended (`shift_ended`, on the
        // socket or as a reconnect rejection). The id is kept for now —
        // Summary still needs it to fetch that shift's report.
        container.read(shiftProvider.notifier).markEnded();
        expect(container.read(shiftProvider), isNotNull);

        // A later reconnect (or the driver talking to Kora again) must get
        // a genuinely new, active shift, not the cached dead one.
        await container.read(shiftProvider.notifier).ensureStarted();
        expect(api.shiftCalls, 2);
      },
    );

    test('markEnded is a one-shot: the shift it starts is not immediately re-started', () async {
      await container.read(shiftProvider.notifier).ensureStarted();
      container.read(shiftProvider.notifier).markEnded();
      await container.read(shiftProvider.notifier).ensureStarted();
      expect(api.shiftCalls, 2);

      // The freshly-started shift is active again: a third call must reuse it.
      await container.read(shiftProvider.notifier).ensureStarted();
      expect(api.shiftCalls, 2);
    });
  });
}
