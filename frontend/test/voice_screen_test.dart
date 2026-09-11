import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/push_to_talk_button.dart';
import 'package:voiceops/features/voice/screens/voice_screen.dart';
import 'package:voiceops/mascot/mascot_display.dart';
import 'package:voiceops/mascot/mascot_state.dart';
import 'package:voiceops/providers/agent_state_provider.dart';
import 'package:voiceops/providers/push_to_talk_provider.dart';

import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('offline composition and controls at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildVoiceOpsTheme(),
            home: const Scaffold(body: VoiceScreen()),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Map preview · sample route'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('map-preview'))).height,
        closeTo(size.height * 0.45, 0.01),
      );
      expect(
        tester.widget<MascotDisplay>(find.byType(MascotDisplay)).material,
        OrbMaterial.chrome,
      );
      final ptt = find.byType(PushToTalkButton);
      expect(tester.getSize(ptt).shortestSide, greaterThanOrEqualTo(80));
      for (final state in PushToTalkState.values) {
        expect(container.read(pushToTalkProvider), state);
        await tester.tap(ptt);
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(container.read(pushToTalkProvider), PushToTalkState.idle);

      for (final text in [
        '24 Adeola Odeku Street',
        'Where am I heading next?',
      ]) {
        await tester.ensureVisible(find.text(text));
        await tester.pump();
        expect(find.text(text).hitTestable(), findsOneWidget);
      }
      const actions = {
        'Find my next stop': AgentState.mapping,
        "What's left on my list": AgentState.taskWorking,
        'Call the customer': AgentState.calling,
        'Give me my summary': AgentState.summarizing,
      };
      for (final action in actions.entries) {
        await tester.ensureVisible(find.text(action.key));
        await tester.pump();
        await tester.tap(find.text(action.key));
        expect(container.read(agentStateProvider), AgentState.thinking);
        await tester.pump(const Duration(milliseconds: 900));
        expect(container.read(agentStateProvider), action.value);
        expect(
          tester.widget<MascotDisplay>(find.byType(MascotDisplay)).state,
          action.value,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }
      expect(ptt.hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
