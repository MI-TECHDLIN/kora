import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/push_to_talk_button.dart';
import 'package:voiceops/providers/push_to_talk_provider.dart';

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

  testWidgets('cycles four distinct states; only recording is live lime', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

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
    for (final expected in PushToTalkState.values) {
      expect(container.read(pushToTalkProvider), expected);
      seen[expected] = decorationOf(tester);

      final isLive = seen[expected]!.color == VoiceOpsColors.live;
      expect(isLive, expected == PushToTalkState.recording);

      await tester.tap(find.byType(PushToTalkButton));
      await tester.pump();
    }
    // Wrapped back around to idle.
    expect(container.read(pushToTalkProvider), PushToTalkState.idle);
    // Every state has its own treatment.
    expect(seen.values.toSet().length, PushToTalkState.values.length);
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
