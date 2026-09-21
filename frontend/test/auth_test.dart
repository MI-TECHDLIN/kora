import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:voiceops/app/main_shell.dart';
import 'package:voiceops/app/router.dart';
import 'package:voiceops/core/audio/voice_recorder.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/primary_button.dart';
import 'package:voiceops/features/auth/data/auth_repository.dart';
import 'package:voiceops/features/auth/screens/sign_in_screen.dart';
import 'package:voiceops/features/auth/screens/sign_up_screen.dart';
import 'package:voiceops/features/auth/screens/welcome_screen.dart';
import 'package:voiceops/features/auth/validation.dart';
import 'package:voiceops/features/auth/widgets/auth_controls.dart';
import 'package:voiceops/features/auth/widgets/auth_text_field.dart';
import 'package:voiceops/features/auth/widgets/terms_agreement.dart';
import 'package:voiceops/features/onboarding/screens/onboarding_flow.dart';
import 'package:voiceops/features/onboarding/screens/onboarding_screen_2.dart';
import 'package:voiceops/features/voice/screens/voice_screen.dart';
import 'package:voiceops/features/voice_onboarding/screens/voice_onboarding_screen.dart';
import 'package:voiceops/main.dart';
import 'package:voiceops/mascot/mascot_display.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/location_provider.dart';
import 'package:voiceops/providers/co_rider_voice_provider.dart';
import 'package:voiceops/providers/onboarding_provider.dart';
import 'package:voiceops/providers/voice_onboarding_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  // The co-rider and background animate forever, so step time explicitly
  // instead of pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(KoraMotion.slow * 2);
  }

  /// Boots the real app (router and auth gate included) on a phone-sized
  /// view, against a fake Supabase: nothing touches the network. Onboarding
  /// comes before the gate, so it starts already completed unless
  /// [onboarded] is false (test/onboarding_test.dart covers each screen).
  Future<FakeAuthRepository> pumpApp(
    WidgetTester tester, {
    Size logical = phone,
    bool onboarded = true,
  }) async {
    final auth = FakeAuthRepository();
    tester.view.physicalSize = logical * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          onboardingCompletedAtLaunchProvider.overrideWithValue(onboarded),
          onboardingStoreProvider.overrideWithValue(
            FakeOnboardingStore(completed: onboarded),
          ),
          // A never-shown store, like a fresh device: sign-up tests below
          // rely on the post-sign-up voice step showing.
          voiceOnboardingStoreProvider.overrideWithValue(
            FakeVoiceOnboardingStore(),
          ),
          // Onboarding's Power screen checks the mic and location.
          voiceRecorderProvider.overrideWithValue(FakeRecorder()),
          locationSourceProvider.overrideWithValue(FakeLocationSource()),
          // The post-sign-up voice step reads these; no real storage in tests.
          voiceOnboardingStoreProvider.overrideWithValue(
            FakeVoiceOnboardingStore(),
          ),
          coRiderVoiceStoreProvider.overrideWithValue(FakeCoRiderVoiceStore()),
        ],
        child: const KoraApp(),
      ),
    );
    await settle(tester);
    return auth;
  }

  // The forms scroll: bring each target into view, and lay out the new
  // scroll offset, before touching it.
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> enter(WidgetTester tester, String label, String text) async {
    final field = find.descendant(
      of: find.widgetWithText(AuthTextField, label),
      matching: find.byType(EditableText),
    );
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.enterText(field, text);
    // A focused field scrolls itself on screen; let that finish.
    await tester.pump(KoraMotion.slow);
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await settle(tester);
  }

  Finder link(String text) => find.text(text, findRichText: true);
  final toSignIn = link('Already have an account? Sign in');
  final toSignUp = link("Don't have an account? Sign up");
  final createAccount = find.widgetWithText(PrimaryButton, SignUpScreen.title);
  final signIn = find.widgetWithText(PrimaryButton, SignInScreen.title);

  Future<void> fillSignUp(WidgetTester tester) async {
    await enter(tester, 'Full name', '  Ada Obi ');
    await enter(tester, 'Email', ' ada@voiceops.test ');
    await enter(tester, 'Password', 'correct-horse');
    await enter(tester, 'Phone number', '+234 801-234-5678');
  }

  testWidgets('a first launch shows onboarding, then welcome, then sign up', (
    tester,
  ) async {
    final auth = await pumpApp(tester, onboarded: false);

    // Onboarding comes before the auth gate, even with no session…
    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);

    // …and deep links bounce back to it rather than to welcome.
    final router = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingFlow)),
    ).read(routerProvider);
    for (final location in [AppRoutes.map, AppRoutes.signUp]) {
      router.go(location);
      await settle(tester);
      expect(find.byType(OnboardingFlow), findsOneWidget, reason: location);
    }

    // Splash → Hook → Power; Next on Power finishes into welcome.
    await tap(tester, find.text('Get started'));
    await tap(tester, find.bySemanticsLabel('Next'));
    expect(find.byType(OnboardingPower), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Next'));
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await tap(tester, find.text('Get started'));
    expect(find.byType(SignUpScreen), findsOneWidget);
    await fillSignUp(tester);
    await tap(tester, find.byType(Checkbox));
    await tap(tester, createAccount);

    // The session lands past onboarding — but a fresh sign-up on a device
    // that has never shown it first meets the co-rider voice step.
    expect(auth.lastSignUp, isNotNull);
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    await tap(tester, find.text('Continue'));
    expect(find.byType(VoiceOnboardingScreen), findsNothing);
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(VoiceScreen), findsOneWidget);
  });

  testWidgets('signed out, the app is gated to welcome, sign up and sign in', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text(WelcomeScreen.headline), findsOneWidget);
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(MainShell), findsNothing);
    // Pre-onboarding: the holographic co-rider, as in onboarding.
    expect(
      OrbMaterialScope.of(tester.element(find.byType(MascotDisplay))),
      OrbMaterial.holographic,
    );

    // Deep links into the app bounce back to welcome without a session.
    final router = ProviderScope.containerOf(
      tester.element(find.byType(WelcomeScreen)),
    ).read(routerProvider);
    router.go(AppRoutes.map);
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    await tap(tester, find.text('Get started'));
    expect(find.byType(SignUpScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing); // covered, offstage

    // System back steps down to welcome instead of leaving the app.
    await systemBack(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(SignUpScreen), findsNothing);

    await tap(tester, toSignIn);
    expect(find.byType(SignInScreen), findsOneWidget);
    await tap(tester, toSignUp);
    expect(find.byType(SignUpScreen), findsOneWidget);
    await tap(tester, toSignIn);
    expect(find.byType(SignInScreen), findsOneWidget);

    await tap(tester, find.byTooltip('Back'));
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('sign up validates every field and the terms gate first', (
    tester,
  ) async {
    final auth = await pumpApp(tester);
    await tap(tester, find.text('Get started'));

    // Empty form: every field and the terms box complain; nothing is sent.
    await tap(tester, createAccount);
    for (final error in [
      'Your full name is required',
      'Your email is required',
      'A password is required',
      'Your phone number is required',
      TermsAgreement.errorText,
    ]) {
      expect(find.text(error), findsOneWidget, reason: error);
    }
    expect(auth.lastSignUp, isNull);

    await enter(tester, 'Email', 'ada@');
    await enter(tester, 'Password', 'short');
    await enter(tester, 'Phone number', '0801 234 5678');
    await tap(tester, createAccount);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(find.textContaining('Include your country code'), findsOneWidget);
    expect(auth.lastSignUp, isNull);

    // Valid fields but no agreement: still gated.
    await fillSignUp(tester);
    await tap(tester, createAccount);
    expect(find.text(TermsAgreement.errorText), findsOneWidget);
    expect(auth.lastSignUp, isNull);

    // The privacy link opens its bundled document and does not tick the box.
    await tester.tapOnText(
      find.textRange.ofSubstring(LegalDocument.privacy.title),
    );
    await settle(tester);
    expect(
      find.text('Kora — Privacy Policy', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Voice audio — captured while you talk to the co-rider assistant',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    await tap(tester, find.byTooltip('Close Privacy Policy'));

    await tap(tester, find.byType(Checkbox));
    expect(find.text(TermsAgreement.errorText), findsNothing);
    await tap(tester, createAccount);

    final sent = auth.lastSignUp!;
    expect(sent.fullName, 'Ada Obi');
    expect(sent.email, 'ada@voiceops.test');
    expect(sent.password, 'correct-horse');
    expect(sent.phone, '+2348012345678'); // E.164 for drivers.phone

    // The session lands: onboarding is behind the driver, and a never-shown
    // device meets the voice step before the gate hands over to the main app.
    expect(find.byType(SignUpScreen), findsNothing);
    expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    await tap(tester, find.text('Continue'));
    expect(find.byType(MainShell), findsOneWidget);
    expect(auth.profileChecks, 1);
  });

  testWidgets('the terms link opens the matching bundled document', (
    tester,
  ) async {
    await pumpApp(tester);
    await tap(tester, find.text('Get started'));

    // The last field is focused and the keyboard is up, which leaves the
    // terms row at the bottom of what's still visible.
    await enter(tester, 'Phone number', '+234 801 234 5678');
    for (var i = 1; i <= 10; i++) {
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * 3 * i / 10);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(KoraMotion.slow);
    final box = find.byType(Checkbox);
    expect(
      tester.getRect(box).bottom,
      greaterThan(phone.height - 300 - 60),
      reason: 'the terms row should sit just above the keyboard',
    );

    // Tapping the terms link opens the scrollable document without agreeing.
    await tester.tapOnText(
      find.textRange.ofSubstring(LegalDocument.terms.title),
    );
    await settle(tester);
    expect(
      find.text('Kora — Terms of Service', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Kora is a voice-driven delivery driver assistant',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(tester.widget<Checkbox>(box).value, isFalse);

    await tap(tester, find.byTooltip('Close Terms of Service'));
    await tester.tap(box);
    await settle(tester);
    expect(tester.widget<Checkbox>(box).value, isTrue);
  });

  testWidgets('sign up waiting on email confirmation stays signed out', (
    tester,
  ) async {
    final auth = await pumpApp(tester)
      ..signUpResult = SignUpResult.confirmEmail;
    await tap(tester, find.text('Get started'));
    await fillSignUp(tester);
    await tap(tester, find.byType(Checkbox));
    await tap(tester, createAccount);

    expect(find.text('Check your inbox'), findsOneWidget);
    expect(find.textContaining('ada@voiceops.test'), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
    expect(auth.profileChecks, 0);

    await tap(tester, find.text('Go to sign in'));
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('sign in shows a Supabase failure, then gets in', (tester) async {
    final auth = await pumpApp(tester);
    await tap(tester, toSignIn);

    await tap(tester, signIn);
    expect(find.text('Your email is required'), findsOneWidget);
    expect(find.text('Your password is required'), findsOneWidget);
    expect(auth.lastSignIn, isNull);

    await enter(tester, 'Email', 'ada@voiceops.test');
    await enter(tester, 'Password', 'wrong');
    auth.failure = const AuthFailure("That email and password don't match.");
    await tap(tester, signIn);
    expect(find.byType(AuthErrorBanner), findsOneWidget);
    expect(find.text("That email and password don't match."), findsOneWidget);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    auth.failure = null;
    await enter(tester, 'Password', 'correct-horse');
    await tap(tester, signIn);
    expect(auth.lastSignIn, (
      email: 'ada@voiceops.test',
      password: 'correct-horse',
    ));
    expect(find.byType(MainShell), findsOneWidget);
  });

  testWidgets('Google sign-in starts from both forms', (tester) async {
    final auth = await pumpApp(tester);

    await tap(tester, toSignIn);
    await tap(tester, find.byType(GoogleButton));
    expect(auth.googleCalls, 1);

    auth.failure = const AuthFailure(
      "Couldn't open Google sign-in. Try again.",
    );
    await tap(tester, toSignUp);
    await tap(tester, find.byType(GoogleButton));
    expect(auth.googleCalls, 2);
    expect(
      find.text("Couldn't open Google sign-in. Try again."),
      findsOneWidget,
    );
  });

  testWidgets('a drivers row that cannot be created is reported, not hidden', (
    tester,
  ) async {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');

    const failure = DriverProfileException(
      "You're signed in, but your driver profile couldn't be set up yet.",
      detail: 'drivers INSERT rejected by RLS (no INSERT policy)',
    );
    final auth = await pumpApp(tester)
      ..profileFailure = failure;
    await tap(tester, toSignIn);
    await enter(tester, 'Email', 'ada@voiceops.test');
    await enter(tester, 'Password', 'correct-horse');
    await tap(tester, signIn);
    debugPrint = originalDebugPrint; // must be restored inside the test body

    // Auth itself succeeded, so the driver moves on…
    expect(find.byType(MainShell), findsOneWidget);
    // …but the missing profile is on screen and in the log.
    expect(find.text(failure.message), findsOneWidget);
    expect(auth.profileChecks, 1);
    expect(logs, contains(contains(failure.detail)));

    // Let the notice time out so no timer outlives the test.
    await tester.pump(KoraMotion.notice);
    await settle(tester);
    expect(find.text(failure.message), findsNothing);
  });

  for (final size in [const Size(320, 568), phone]) {
    testWidgets('auth screens lay out at $size without overflow', (
      tester,
    ) async {
      // Any RenderFlex overflow fails the test.
      await pumpApp(tester, logical: size);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      final cta = tester.getRect(find.text('Get started'));
      expect(cta.bottom, lessThanOrEqualTo(size.height));

      await tap(tester, find.text('Get started'));
      await tap(tester, createAccount); // every error showing at once
      expect(find.text(TermsAgreement.errorText), findsOneWidget);

      await tap(tester, toSignIn);
      await tap(tester, signIn);
      expect(find.byType(SignInScreen), findsOneWidget);
    });
  }

  group('AuthValidators', () {
    test('email', () {
      expect(AuthValidators.email('ada@voiceops.test'), isNull);
      expect(AuthValidators.email(' ada@voiceops.test '), isNull);
      expect(AuthValidators.email(''), isNotNull);
      expect(AuthValidators.email('ada@voiceops'), isNotNull);
      expect(AuthValidators.email('ada voiceops.test'), isNotNull);
    });

    test('phone must be E.164 once spacing is stripped', () {
      expect(
        AuthValidators.normalizePhone(' +234 (801) 234-5678 '),
        '+2348012345678',
      );
      expect(AuthValidators.phone('+234 801 234 5678'), isNull);
      expect(AuthValidators.phone('+1 415 555 0100'), isNull);
      expect(AuthValidators.phone('08012345678'), isNotNull); // no country
      expect(AuthValidators.phone('+0 801 234 5678'), isNotNull);
      expect(AuthValidators.phone('+234 80'), isNotNull);
      expect(AuthValidators.phone('+234 801 234 5678 999 99'), isNotNull);
    });

    test('passwords: new ones need length, sign-in only presence', () {
      expect(AuthValidators.newPassword('1234567'), isNotNull);
      expect(AuthValidators.newPassword('12345678'), isNull);
      expect(AuthValidators.password('1'), isNull);
      expect(AuthValidators.password(''), isNotNull);
    });
  });

  test('the gate only accepts a live, unexpired session', () {
    Session session(Duration fromNow) => Session(
      accessToken: 'not-a-real-token',
      tokenType: 'bearer',
      user: const User(
        id: 'driver-1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-09-12T00:00:00Z',
      ),
    )..expiresAt = DateTime.now().add(fromNow).millisecondsSinceEpoch ~/ 1000;

    expect(SupabaseAuthRepository.isUsable(null), isFalse);
    expect(
      SupabaseAuthRepository.isUsable(session(const Duration(hours: 1))),
      isTrue,
    );
    expect(
      SupabaseAuthRepository.isUsable(session(const Duration(minutes: -5))),
      isFalse,
    );
  });
}

/// A mid-range Android phone, in logical pixels.
const phone = Size(360, 780);
