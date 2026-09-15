import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/push_to_talk_button.dart';
import 'package:voiceops/features/voice/screens/voice_screen.dart';
import 'package:voiceops/mascot/mascot_display.dart';
import 'package:voiceops/mascot/mascot_state.dart';
import 'package:voiceops/providers/agent_state_provider.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/push_to_talk_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('offline composition and controls at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          ...offlineOverrides(),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(signedIn: true),
          ),
        ],
      );
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
      final mapPreview = find.byKey(const Key('map-preview'));
      expect(
        tester.getSize(mapPreview).height,
        size.height < VoiceOpsMap.compactHeight
            ? VoiceOpsSize.mapPreviewCompact
            : VoiceOpsSize.mapPreview,
      );
      final mascot = find.byType(MascotDisplay);
      expect(tester.widget<MascotDisplay>(mascot).material, OrbMaterial.chrome);
      expect(tester.getSize(mascot), const Size.square(VoiceOpsSize.orbVoice));
      final mapRect = tester.getRect(mapPreview);
      final mascotRect = tester.getRect(mascot);
      expect(mapRect.contains(mascotRect.topLeft), isTrue);
      expect(mapRect.contains(mascotRect.bottomRight), isTrue);
      expect(
        tester.getRect(find.text('Your route, together')).right,
        lessThanOrEqualTo(mascotRect.left),
      );
      final ptt = find.byType(PushToTalkButton);
      expect(tester.getSize(ptt).shortestSide, greaterThanOrEqualTo(80));
      expect(mapRect.overlaps(tester.getRect(ptt)), isFalse);
      // The hint under the button tells the driver what a tap does now.
      const hints = {
        PushToTalkState.idle: 'Tap to talk to your co-rider',
        PushToTalkState.recording: 'Listening · tap to end',
        PushToTalkState.processing: 'Working on it…',
        PushToTalkState.speaking: 'Tap to interrupt',
      };
      for (final hint in hints.entries) {
        container.read(pushToTalkProvider.notifier).set(hint.key);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<Text>(find.byKey(const Key('ptt-hint'))).data,
          hint.value,
        );
      }
      container.read(pushToTalkProvider.notifier).set(PushToTalkState.idle);
      // A tap opens the session and starts the mic (offline fakes).
      await tester.tap(ptt);
      await tester.pump();
      expect(container.read(pushToTalkProvider), PushToTalkState.recording);

      final firstAction = find.text('Find my next stop');
      expect(find.text('Quick actions').hitTestable(), findsOneWidget);
      expect(firstAction.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(firstAction).dy,
        lessThan(tester.getTopLeft(ptt).dy),
      );

      for (final text in ['1400 Lavaca Street', 'Where am I heading next?']) {
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
      final actionsRail = find.descendant(
        of: find.byKey(const Key('quick-actions-rail')),
        matching: find.byType(Scrollable),
      );
      for (final action in actions.entries) {
        await tester.scrollUntilVisible(
          find.text(action.key),
          200,
          scrollable: actionsRail,
        );
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
