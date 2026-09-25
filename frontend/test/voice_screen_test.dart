import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:voiceops/core/realtime/voice_events.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/push_to_talk_button.dart';
import 'package:voiceops/features/map/data/location_source.dart';
import 'package:voiceops/features/map/data/map_route.dart';
import 'package:voiceops/features/settings/screens/settings_screen.dart';
import 'package:voiceops/features/voice/screens/voice_screen.dart';
import 'package:voiceops/mascot/mascot_display.dart';
import 'package:voiceops/mascot/mascot_state.dart';
import 'package:voiceops/providers/agent_state_provider.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/home_preferences_provider.dart';
import 'package:voiceops/providers/map_route_provider.dart';
import 'package:voiceops/providers/push_to_talk_provider.dart';
import 'package:voiceops/providers/shift_provider.dart';
import 'package:voiceops/providers/transcript_provider.dart';
import 'package:voiceops/providers/voice_session_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'map_route_test.dart' show sampleMapRoute;
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  late FakeHomePreferencesStore homePreferencesStore;
  late FakeLocationSource location;
  late FakeVoiceConnector connector;
  late ProviderContainer container;

  setUp(() {
    homePreferencesStore = FakeHomePreferencesStore();
    location = FakeLocationSource();
    connector = FakeVoiceConnector();
    container = ProviderContainer(
      overrides: [
        ...offlineOverrides(
          connector: connector,
          location: location,
          homePreferencesStore: homePreferencesStore,
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildKoraTheme(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('Home is minimal and demo-free at $size', (tester) async {
      await pumpScreen(tester, const VoiceScreen(), size: size);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('home-status-card')), findsOneWidget);
      expect(find.byKey(const Key('home-status-empty')), findsOneWidget);
      expect(find.text('READY FOR YOUR SHIFT'), findsOneWidget);
      expect(find.text('No active route'), findsOneWidget);

      // Optional features start hidden for new and existing users.
      expect(find.byKey(const Key('quick-actions-rail')), findsNothing);
      expect(find.byKey(const Key('home-conversation')), findsNothing);
      expect(find.byKey(const Key('home-location')), findsNothing);

      // The old illustrative map and every hard-coded demo detail are gone.
      expect(find.byKey(const Key('map-preview')), findsNothing);
      expect(find.textContaining('sample', findRichText: true), findsNothing);
      expect(find.text('1400 Lavaca Street'), findsNothing);
      expect(find.text('Elena R.'), findsNothing);
      expect(find.text('Where am I heading next?'), findsNothing);

      final mascot = find.byType(MascotDisplay);
      expect(tester.widget<MascotDisplay>(mascot).material, OrbMaterial.chrome);
      expect(tester.getSize(mascot), const Size.square(KoraSize.orbHero));

      final ptt = find.byType(PushToTalkButton);
      expect(tester.getSize(ptt).shortestSide, greaterThanOrEqualTo(80));
      expect(ptt.hitTestable(), findsOneWidget);
    });
  }

  testWidgets('status card shows only the real active shift and route', (
    tester,
  ) async {
    container
        .read(mapRouteProvider.notifier)
        .show(MapRoute.fromJson(sampleMapRoute()));
    await container.read(shiftProvider.notifier).ensureStarted();
    await pumpScreen(tester, const VoiceScreen());

    expect(find.byKey(const Key('home-status-empty')), findsNothing);
    expect(find.byKey(const Key('home-status-populated')), findsOneWidget);
    expect(find.text('SHIFT ACTIVE'), findsOneWidget);
    expect(find.text('NEXT STOP · 4'), findsOneWidget);
    expect(find.text('Jordan Lee'), findsOneWidget);
    expect(find.text('812 Lavaca St, Austin, TX 78701'), findsOneWidget);
    expect(find.text('11 mins'), findsOneWidget);
  });

  testWidgets('Settings switches show and hide each optional Home feature', (
    tester,
  ) async {
    Future<void> setFeature(Key toggleKey, Key featureKey, bool enabled) async {
      await pumpScreen(tester, const SettingsScreen());
      final toggle = find.descendant(
        of: find.byKey(toggleKey),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(toggle);
      expect(tester.widget<Switch>(toggle).value, !enabled);
      await tester.tap(toggle);
      await tester.pump();

      await pumpScreen(tester, const VoiceScreen());
      expect(find.byKey(featureKey), enabled ? findsOneWidget : findsNothing);
    }

    await setFeature(
      const Key('quick-actions-toggle'),
      const Key('quick-actions-rail'),
      true,
    );
    expect(homePreferencesStore.value.quickActionsEnabled, isTrue);
    await setFeature(
      const Key('quick-actions-toggle'),
      const Key('quick-actions-rail'),
      false,
    );
    expect(homePreferencesStore.value.quickActionsEnabled, isFalse);

    await setFeature(
      const Key('conversation-toggle'),
      const Key('home-conversation'),
      true,
    );
    expect(homePreferencesStore.value.conversationEnabled, isTrue);
    await setFeature(
      const Key('conversation-toggle'),
      const Key('home-conversation'),
      false,
    );
    expect(homePreferencesStore.value.conversationEnabled, isFalse);

    await setFeature(
      const Key('location-toggle'),
      const Key('home-location'),
      true,
    );
    expect(homePreferencesStore.value.locationEnabled, isTrue);
    await setFeature(
      const Key('location-toggle'),
      const Key('home-location'),
      false,
    );
    expect(homePreferencesStore.value.locationEnabled, isFalse);
  });

  testWidgets('enabled sections render live content instead of examples', (
    tester,
  ) async {
    homePreferencesStore.value = const HomePreferences(
      quickActionsEnabled: true,
      conversationEnabled: true,
      locationEnabled: true,
    );
    // Recreate so the provider loads the scripted persisted preferences.
    container.dispose();
    container = ProviderContainer(
      overrides: [
        ...offlineOverrides(
          connector: connector,
          location: location,
          homePreferencesStore: homePreferencesStore,
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
      ],
    );
    container
        .read(transcriptProvider.notifier)
        .add(SpeakerRole.agent, 'The loading bay is ready for you.');
    await pumpScreen(tester, const VoiceScreen());

    location.emit(const LocationFix(LatLng(6.4600, 3.3900), accuracy: 8));
    await tester.pump();

    expect(find.byKey(const Key('quick-actions-rail')), findsOneWidget);
    expect(find.text('The loading bay is ready for you.'), findsOneWidget);
    expect(find.text('6.46000, 3.39000 · ±8 m'), findsOneWidget);

    await tester.ensureVisible(find.text('Find my next stop'));
    await tester.tap(find.text('Find my next stop'));
    await tester.pump();
    expect(container.read(pushToTalkProvider), PushToTalkState.recording);
    await container.read(voiceSessionProvider.notifier).disconnect();
    await tester.pump();
  });

  testWidgets('push-to-talk hints and co-rider moods remain state-driven', (
    tester,
  ) async {
    await pumpScreen(tester, const VoiceScreen());

    const hints = {
      PushToTalkState.idle: 'Tap to talk to your co-rider',
      PushToTalkState.recording: 'Listening · tap to end',
      PushToTalkState.processing: 'Working on it…',
      PushToTalkState.speaking: 'Tap to interrupt',
    };
    for (final hint in hints.entries) {
      container.read(pushToTalkProvider.notifier).set(hint.key);
      await tester.pump(KoraMotion.base);
      expect(
        tester.widget<Text>(find.byKey(const Key('ptt-hint'))).data,
        hint.value,
      );
    }

    for (final mood in AgentState.values) {
      container.read(agentStateProvider.notifier).setState(mood);
      await tester.pump();
      await tester.pump(KoraMotion.orbMorph);
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<MascotDisplay>(find.byType(MascotDisplay)).state,
        mood,
      );
      expect(find.text(mood.label ?? 'Ready when you are'), findsOneWidget);
    }
  });
}
