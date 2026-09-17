import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/push_to_talk_button.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/push_to_talk_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  BoxDecoration decorationOf(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(PushToTalkButton),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  ProviderContainer offlineContainer({FakeRecorder? recorder}) {
    final container = ProviderContainer(
      overrides: [
        ...offlineOverrides(recorder: recorder),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('four distinct states; only recording is live lime', (
    tester,
  ) async {
    final container = offlineContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildVoiceOpsTheme(),
          home: const Scaffold(body: Center(child: PushToTalkButton())),
        ),
      ),
    );

    final size = tester.getSize(find.byType(PushToTalkButton));
    expect(size.width, greaterThanOrEqualTo(VoiceOpsSize.pushToTalkMin));
    expect(size.height, greaterThanOrEqualTo(VoiceOpsSize.pushToTalkMin));

    final seen = <PushToTalkState, BoxDecoration>{};
    for (final state in PushToTalkState.values) {
      container.read(pushToTalkProvider.notifier).set(state);
      await tester.pump(VoiceOpsMotion.slow);
      seen[state] = decorationOf(tester);

      final isLive = seen[state]!.color == VoiceOpsColors.live;
      expect(isLive, state == PushToTalkState.recording);
    }
    // Every state has its own treatment.
    expect(seen.values.toSet().length, PushToTalkState.values.length);
    container.read(pushToTalkProvider.notifier).set(PushToTalkState.idle);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('a tap goes to the voice session: idle starts the mic', (
    tester,
  ) async {
    final recorder = FakeRecorder();
    final container = offlineContainer(recorder: recorder);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildVoiceOpsTheme(),
          home: const Scaffold(body: Center(child: PushToTalkButton())),
        ),
      ),
    );

    await tester.tap(find.byType(PushToTalkButton));
    await tester.pump();
    expect(container.read(pushToTalkProvider), PushToTalkState.recording);
    expect(recorder.isRecording, isTrue);
    expect(decorationOf(tester).color, VoiceOpsColors.live);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  test('live lime never leaks into the Material colour scheme', () {
    final scheme = buildVoiceOpsTheme().colorScheme;
    final roles = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      scheme.surface,
      scheme.surfaceTint,
      scheme.inversePrimary,
    ];
    expect(roles, isNot(contains(VoiceOpsColors.live)));
  });
}
