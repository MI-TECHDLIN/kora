import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voiceops/app/main_shell.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/auth/screens/sign_up_screen.dart';
import 'package:voiceops/features/auth/screens/welcome_screen.dart';
import 'package:voiceops/features/onboarding/screens/onboarding_flow.dart';
import 'package:voiceops/features/onboarding/screens/onboarding_screen_0.dart';
import 'package:voiceops/features/onboarding/screens/onboarding_screen_1.dart';
import 'package:voiceops/features/onboarding/screens/onboarding_screen_2.dart';
import 'package:voiceops/main.dart';
import 'package:voiceops/mascot/mascot_display.dart';
import 'package:voiceops/providers/auth_provider.dart';

import 'fake_auth.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  // The co-rider and background animate forever, so step time explicitly
  // instead of pumpAndSettle. Covers page turns and the card-stack entrance.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(VoiceOpsMotion.stagger + VoiceOpsMotion.slow);
  }

  /// Boots the real app (router redirect included) on a phone-sized view,
  /// as on a first launch: signed out, so onboarding comes before the auth
  /// gate. No backend, no platform permissions: everything here is local
  /// (test/auth_test.dart covers the gate itself).
  Future<void> pumpApp(WidgetTester tester, {Size logical = phone}) async {
    tester.view.physicalSize = logical * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: const VoiceOpsApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> swipe(WidgetTester tester, {required bool forward}) async {
    await tester.fling(
      find.byType(PageView),
      Offset(forward ? -300 : 300, 0),
      1000,
    );
    await settle(tester);
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await settle(tester);
  }

  Finder next() => find.bySemanticsLabel('Next');

  /// The Next button as the live semantics tree announces it right now.
  FinderBase<SemanticsNode> liveNext() => find.semantics.byLabel('Next');

  testWidgets('walks all three screens verbatim and hands off to welcome', (
    tester,
  ) async {
    await pumpApp(tester);

    // 0 — Splash.
    expect(find.bySemanticsLabel(OnboardingSplash.headline), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(liveNext(), findsNothing); // splash has its own CTA
    expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);
    // PRD §4.7: no skip button anywhere in the flow.
    expect(
      find.textContaining(RegExp('skip', caseSensitive: false)),
      findsNothing,
    );
    expect(
      OrbMaterialScope.of(tester.element(find.byType(MascotDisplay).first)),
      OrbMaterial.holographic,
    );

    await tester.tap(find.text('Get started'));
    await settle(tester);

    // 1 — Hook.
    expect(find.byType(OnboardingHook), findsOneWidget);
    expect(find.text('Waking up your co-rider'), findsOneWidget);
    expect(find.text("Say the word. It's already moving."), findsOneWidget);
    expect(
      find.text(
        'One sentence starts your whole shift — no taps, no glancing down.',
      ),
      findsOneWidget,
    );
    expect(find.byType(MascotDisplay), findsOneWidget);
    expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);

    await tester.tap(next());
    await settle(tester);

    // 2 — Power, with the placeholder driver name.
    expect(find.byType(OnboardingPower), findsOneWidget);
    expect(
      find.text(
        "Hello, Mary — here's what it caught already",
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('NEXT STOP'), findsOneWidget);
    expect(find.text('Mic access'), findsOneWidget);
    expect(find.text('ACTION REQUIRED'), findsOneWidget);
    expect(
      find.textContaining('so it can hear you over road noise'),
      findsOneWidget,
    );
    expect(find.text('Live route'), findsOneWidget);
    expect(
      find.text('Three things happen at once. You do nothing.'),
      findsOneWidget,
    );

    // The mic card is a visual mock: allowing it needs no real permission.
    // The square-glyph test font makes text far wider than Plus Jakarta
    // Sans, so taller pages scroll; bring each CTA into view first.
    await tester.ensureVisible(find.text('Allow mic'));
    await tester.tap(find.text('Allow mic'));
    await settle(tester);
    expect(find.text('Mic allowed'), findsOneWidget);
    expect(find.text('ACTION REQUIRED'), findsNothing);

    // Power is the last screen: all dots filled, and Next finishes.
    expect(find.bySemanticsLabel('Step 3 of 3'), findsOneWidget);
    expect(liveNext(), findsOneWidget);
    await tester.tap(next());
    await settle(tester);

    // The router redirect hands the signed-out driver to welcome's
    // "Get started", which leads into sign-up.
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(MainShell), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.ensureVisible(find.text('Get started'));
    await tester.tap(find.text('Get started'));
    await settle(tester);
    expect(find.byType(SignUpScreen), findsOneWidget);
  });

  testWidgets('swipes both ways and system back steps back a screen', (
    tester,
  ) async {
    await pumpApp(tester);

    await swipe(tester, forward: true);
    expect(find.byType(OnboardingHook), findsOneWidget);
    await swipe(tester, forward: true);
    expect(find.byType(OnboardingPower), findsOneWidget);

    // Power is the end: swiping on does not finish onboarding by itself.
    await swipe(tester, forward: true);
    expect(find.byType(OnboardingPower), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);

    await swipe(tester, forward: false);
    expect(find.byType(OnboardingHook), findsOneWidget);
    await swipe(tester, forward: true);
    expect(find.byType(OnboardingPower), findsOneWidget);

    // Back walks the pages instead of leaving onboarding.
    await systemBack(tester);
    expect(find.byType(OnboardingHook), findsOneWidget);
    await systemBack(tester);
    expect(find.byType(OnboardingSplash), findsOneWidget);
    expect(find.byType(OnboardingFlow), findsOneWidget);
  });

  for (final size in [const Size(320, 568), const Size(360, 640)]) {
    testWidgets('every screen lays out at $size without overflow', (
      tester,
    ) async {
      // Small phones; any RenderFlex overflow fails the test.
      await pumpApp(tester, logical: size);
      for (final screen in [
        OnboardingSplash,
        OnboardingHook,
        OnboardingPower,
      ]) {
        expect(find.byType(screen), findsOneWidget);
        if (screen != OnboardingPower) await swipe(tester, forward: true);
      }
      // …and the Next button that finishes stays on screen.
      expect(tester.getRect(next()).bottom, lessThanOrEqualTo(size.height));
    });
  }
}

/// A mid-range Android phone, in logical pixels.
const phone = Size(360, 780);
