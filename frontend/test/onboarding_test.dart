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
import 'package:voiceops/providers/onboarding_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  // The co-rider and background animate forever, so step time explicitly
  // instead of pumpAndSettle. Covers page turns and the card-stack entrance.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(KoraMotion.stagger + KoraMotion.slow);
  }

  /// Boots the real app (router redirect included) on a phone-sized view,
  /// as on a first launch: signed out, so onboarding comes before the auth
  /// gate. No backend and no OS prompts: the mic, location and saved
  /// onboarding flag are fakes the test can script (test/auth_test.dart
  /// covers the gate itself).
  Future<void> pumpApp(
    WidgetTester tester, {
    Size logical = phone,
    FakeRecorder? recorder,
    FakeLocationSource? location,
    FakeOnboardingStore? store,
  }) async {
    tester.view.physicalSize = logical * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final saved = store ?? FakeOnboardingStore();
    await tester.pumpWidget(
      ProviderScope(
        // A new scope per launch, as on a real restart.
        key: UniqueKey(),
        overrides: [
          ...offlineOverrides(
            recorder: recorder,
            location: location,
            onboardingStore: saved,
          ),
          // What main.dart reads before the first frame.
          onboardingCompletedAtLaunchProvider.overrideWithValue(
            await loadOnboardingCompleted(saved),
          ),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: const KoraApp(),
      ),
    );
    await settle(tester);
  }

  /// From the splash to Power, the last screen.
  Future<void> toPower(WidgetTester tester) async {
    await tester.tap(find.text('Get started'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Next'));
    await settle(tester);
    expect(find.byType(OnboardingPower), findsOneWidget);
  }

  // The square-glyph test font makes text far wider than Plus Jakarta
  // Sans, so taller pages scroll; bring each CTA into view first.
  Future<void> tapInView(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
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
    final recorder = FakeRecorder();
    final location = FakeLocationSource();
    final store = FakeOnboardingStore();
    await pumpApp(tester, recorder: recorder, location: location, store: store);

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
    expect(
      find.textContaining('so it can hear you over road noise'),
      findsOneWidget,
    );
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('It routes you stop to stop.'), findsOneWidget);
    expect(find.text('ACTION REQUIRED'), findsNWidgets(2));
    expect(find.text('Live route'), findsOneWidget);
    expect(
      find.text('Three things happen at once. You do nothing.'),
      findsOneWidget,
    );

    // Nothing has asked the OS yet; each card asks when tapped and shows
    // the real answer.
    expect(recorder.permissionRequests, 0);
    expect(location.permissionRequests, 0);
    await tapInView(tester, find.text('Allow mic'));
    expect(recorder.permissionRequests, 1);
    expect(find.text('Mic allowed'), findsOneWidget);
    expect(find.text('ACTION REQUIRED'), findsOneWidget);
    await tapInView(tester, find.text('Allow location'));
    expect(location.permissionRequests, 1);
    expect(find.text('Location allowed'), findsOneWidget);
    expect(find.text('ACTION REQUIRED'), findsNothing);
    expect(find.text('ALL SET'), findsNWidgets(2));

    // Power is the last screen: all dots filled, and Next finishes.
    expect(find.bySemanticsLabel('Step 3 of 3'), findsOneWidget);
    expect(liveNext(), findsOneWidget);
    await tester.tap(next());
    await settle(tester);
    expect(store.completed, isTrue); // it won't show on the next launch

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

  testWidgets('a refused permission keeps its card asking', (tester) async {
    final recorder = FakeRecorder()..permitted = false;
    final location = FakeLocationSource()..permitted = false;
    await pumpApp(tester, recorder: recorder, location: location);
    await toPower(tester);

    await tapInView(tester, find.text('Allow mic'));
    await tapInView(tester, find.text('Allow location'));
    expect(recorder.permissionRequests, 1);
    expect(location.permissionRequests, 1);
    expect(find.text('ACTION REQUIRED'), findsNWidgets(2));
    expect(find.text('ALL SET'), findsNothing);

    // Asking again goes back to the OS.
    recorder.permitted = true;
    await tapInView(tester, find.text('Allow mic'));
    expect(recorder.permissionRequests, 2);
    expect(find.text('Mic allowed'), findsOneWidget);
    expect(find.text('Allow location'), findsOneWidget);
  });

  testWidgets('permissions granted before show as allowed, without asking', (
    tester,
  ) async {
    final recorder = FakeRecorder()..granted = true;
    final location = FakeLocationSource()..granted = true;
    await pumpApp(tester, recorder: recorder, location: location);
    await toPower(tester);

    expect(find.text('ALL SET'), findsNWidgets(2));
    expect(find.text('Mic allowed'), findsOneWidget);
    expect(find.text('Location allowed'), findsOneWidget);
    expect(find.text('Allow mic'), findsNothing);
    expect(find.text('Allow location'), findsNothing);
    expect(recorder.permissionRequests, 0);
    expect(location.permissionRequests, 0);
  });

  testWidgets('allowing location starts the position stream again', (
    tester,
  ) async {
    // The app starts the stream at launch, before permission exists.
    final location = FakeLocationSource();
    await pumpApp(tester, location: location);
    await toPower(tester);
    final watches = location.watches;
    expect(watches, greaterThan(0));

    await tapInView(tester, find.text('Allow location'));
    expect(location.watches, watches + 1);
  });

  testWidgets('finished onboarding stays finished after a restart', (
    tester,
  ) async {
    final store = FakeOnboardingStore();
    await pumpApp(tester, store: store);
    await toPower(tester);
    await tester.tap(next());
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);

    // Relaunch: a fresh app reading the saved flag goes straight to welcome.
    await pumpApp(tester, store: store);
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);
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

  // The card stack is meant to read as a staggered, tilted pile: every card
  // slides under the one after it. What it may never do is slide far enough
  // to hide what that card shows — the stop's two rows, or an allow button
  // the driver has to reach. Each card is padded by KoraSpacing.lg and
  // slides under the next one by less than that, so the overlap lands on
  // blank card. The tilts used to break it: Transform.rotate leaves its
  // corners outside its box, so a card started higher than the column
  // thought and ate into the one before it.
  group('the Power card stack stays staggered without covering itself', () {
    /// Where [finder] actually lands on screen, tilt included.
    Rect painted(WidgetTester tester, Finder finder) {
      final box = tester.renderObject<RenderBox>(finder);
      return MatrixUtils.transformRect(
        box.getTransformTo(null),
        box.paintBounds,
      );
    }

    /// The card carrying [text]: its outermost painted surface.
    Finder card(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(Container))
        .first;

    /// Pumps Power alone, so the sweep can set a text scale cheaply.
    Future<void> pumpPower(
      WidgetTester tester, {
      required Size size,
      required double textScale,
      required bool allowed,
    }) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildVoiceOpsTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              backgroundColor: KoraMood.lavender.first,
              body: OnboardingPower(
                driverName: 'Mary',
                micAllowed: allowed,
                onAllowMic: () {},
                locationAllowed: allowed,
                onAllowLocation: () {},
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    for (final size in [
      const Size(320, 568),
      const Size(360, 780),
      const Size(390, 844),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final allowed in [false, true]) {
          final state = allowed ? 'allowed' : 'asking';
          testWidgets('$size at ${scale}x text, $state', (tester) async {
            await pumpPower(
              tester,
              size: size,
              textScale: scale,
              allowed: allowed,
            );

            final stop = card('Capitol Hill');
            final mic = card('Mic access');
            final location = card('Location');

            // Everything the card behind shows has to stay uncovered.
            for (final (name, over, under) in [
              ('mic card over NEXT STOP', mic, find.text('NEXT STOP')),
              ('mic card over the stop', mic, find.text('Capitol Hill')),
              ('mic card over the ETA', mic, find.text('12 min')),
              (
                'location card over its title',
                location,
                find.text('Mic access'),
              ),
              (
                'location card over the mic control',
                location,
                find.text(allowed ? 'Mic allowed' : 'Allow mic'),
              ),
              // The teaser paints first (furthest back) and peeks from the
              // top-left corner, the one spot none of the front cards
              // reach — it must stay readable, not swallowed behind them.
              (
                'the stop card over the teaser label',
                stop,
                find.text('Live route'),
              ),
              (
                'the mic card over the teaser label',
                mic,
                find.text('Live route'),
              ),
            ]) {
              final covering = painted(tester, over);
              final covered = painted(tester, under);
              expect(
                covering.overlaps(covered),
                isFalse,
                reason: '$name: $covering covers $covered',
              );
            }

            // The peek is only worth anything if it actually lands inside
            // the unscrolled viewport, not just clear of the front cards —
            // a corner that's technically uncovered but scrolled off is
            // just as invisible to the driver.
            final teaserLabel = painted(tester, find.text('Live route'));
            expect(
              teaserLabel.top < size.height && teaserLabel.bottom > 0,
              isTrue,
              reason:
                  'teaser label $teaserLabel sits outside the '
                  '${size.width}x${size.height} viewport',
            );

            // …while each pair keeps a thin seam: open even at the tilted
            // corners, so the layering reads as deliberate, but no wider than
            // a small spacing step, so this stays a stack and does not
            // quietly become a list.
            for (final (name, over, under) in [
              ('mic card below the stop card', mic, stop),
              ('location card below the mic card', location, mic),
            ]) {
              final seam =
                  painted(tester, over).top - painted(tester, under).bottom;
              expect(
                seam,
                inInclusiveRange(1, KoraSpacing.sm),
                reason: '$name sits $seam apart',
              );
            }
          });
        }
      }
    }

    testWidgets('both allow buttons take a tap through the tilt', (
      tester,
    ) async {
      var mic = 0;
      var location = 0;
      tester.view.physicalSize = phone * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildVoiceOpsTheme(),
          home: Scaffold(
            body: OnboardingPower(
              driverName: 'Mary',
              micAllowed: false,
              onAllowMic: () => mic++,
              locationAllowed: false,
              onAllowLocation: () => location++,
            ),
          ),
        ),
      );
      await settle(tester);

      // Tapped at the centre the tilt actually puts them at.
      await tapInView(tester, find.text('Allow mic'));
      await tapInView(tester, find.text('Allow location'));
      expect(mic, 1);
      expect(location, 1);
    });
  });
}

/// A mid-range Android phone, in logical pixels.
const phone = Size(360, 780);
