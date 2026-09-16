import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:voiceops/app/main_shell.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/push_to_talk_button.dart';
import 'package:voiceops/features/map/data/location_source.dart';
import 'package:voiceops/features/map/screens/map_screen.dart';
import 'package:voiceops/features/map/widgets/map_markers.dart';
import 'package:voiceops/features/onboarding/screens/onboarding_flow.dart';
import 'package:voiceops/features/settings/screens/settings_screen.dart';
import 'package:voiceops/features/voice/screens/voice_screen.dart';
import 'package:voiceops/main.dart';
import 'package:voiceops/mascot/mascot_display.dart';
import 'package:voiceops/providers/onboarding_provider.dart';
import 'package:voiceops/providers/push_to_talk_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'map_route_test.dart' show sampleMapRoute;
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  // The co-rider and background animate forever, so step time explicitly
  // instead of pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(VoiceOpsMotion.slow * 2);
  }

  testWidgets('renders dark, gates on onboarding, then navigates tabs', (
    tester,
  ) async {
    // A mid-range Android phone: 360×780 logical pixels.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...signedInOverrides(), ...offlineOverrides()],
        child: const VoiceOpsApp(),
      ),
    );
    await settle(tester);

    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, VoiceOpsColors.canvas);

    // Onboarding redirect: holographic co-rider, no main shell yet.
    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
    final onboardingOrb = find.byType(MascotDisplay);
    expect(onboardingOrb, findsOneWidget);
    expect(
      OrbMaterialScope.of(tester.element(onboardingOrb)),
      OrbMaterial.holographic,
    );

    // Already signed in, completing the flow (Next on Power) redirects
    // straight into the voice tab (test/onboarding_test.dart covers each
    // screen).
    await tester.tap(find.text('Get started'));
    await settle(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.bySemanticsLabel('Next'));
      await settle(tester);
    }
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(VoiceScreen), findsOneWidget);
    expect(find.byType(MascotDisplay), findsOneWidget); // inline, chrome
    // Chips are real driver commands (PRD §7), never generic assistant ones.
    expect(find.text('Find my next stop'), findsOneWidget);
    expect(find.text('Translate text'), findsNothing);

    // Bottom nav switches branches through go_router.
    await tester.tap(find.bySemanticsLabel('Map'));
    await settle(tester);
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byType(VoiceScreen), findsNothing); // offstage branch
    // Off the voice tab the global overlay floats the co-rider.
    expect(find.byType(MascotDisplay), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Voice'));
    await settle(tester);
    expect(find.byType(VoiceScreen), findsOneWidget);
  });

  testWidgets('voice drives the screens: the next stop opens the route map', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final connector = FakeVoiceConnector();
    final location = FakeLocationSource();
    final container = ProviderContainer(
      overrides: [
        ...signedInOverrides(),
        ...offlineOverrides(connector: connector, location: location),
      ],
    );
    addTearDown(container.dispose);
    container.read(onboardingProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const VoiceOpsApp(),
      ),
    );
    await settle(tester);
    expect(find.byType(VoiceScreen), findsOneWidget);

    // "Take me to my next stop": the mic opens the session and the
    // relay's route tool answers (docs/contracts/interface.md §1).
    await tester.tap(find.byType(PushToTalkButton));
    await settle(tester);
    expect(container.read(pushToTalkProvider), PushToTalkState.recording);
    connector.last
      ..emit({'event': 'agent_state', 'state': 'mapping'})
      ..emit({'event': 'screen_navigate', 'screen': 'map'})
      ..emit(sampleMapRoute());
    await settle(tester);
    location.emit(const LocationFix(LatLng(6.46, 3.39)));
    await settle(tester);

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.byType(StopPin), findsNWidgets(2));
    expect(find.byType(PositionMarker), findsOneWidget);
    expect(find.text('Amara Johnson'), findsOneWidget);
    expect(find.text('11 mins'), findsOneWidget);

    // "Show my vehicle": show_screen opens Settings with the profile's
    // vehicle.
    connector.last.emit({'event': 'screen_navigate', 'screen': 'settings'});
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(const Key('vehicle-card')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // the map-focus grace
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
