import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voiceops/app/main_shell.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/map/screens/map_screen.dart';
import 'package:voiceops/features/voice/screens/voice_screen.dart';
import 'package:voiceops/main.dart';
import 'package:voiceops/mascot/mascot_display.dart';

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

    await tester.pumpWidget(const ProviderScope(child: VoiceOpsApp()));
    await settle(tester);

    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, VoiceOpsColors.canvas);

    // Onboarding redirect: holographic co-rider, no main shell yet.
    expect(find.text('Start Driving'), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
    final onboardingOrb = find.byType(MascotDisplay);
    expect(onboardingOrb, findsOneWidget);
    expect(
      OrbMaterialScope.of(tester.element(onboardingOrb)),
      OrbMaterial.holographic,
    );

    // Completing onboarding redirects into the voice tab.
    await tester.tap(find.text('Start Driving'));
    await settle(tester);
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
}
