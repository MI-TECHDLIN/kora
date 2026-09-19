import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voiceops/app/main_shell.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/primary_button.dart';
import 'package:voiceops/features/auth/screens/sign_in_screen.dart';
import 'package:voiceops/features/auth/screens/sign_up_screen.dart';
import 'package:voiceops/features/auth/widgets/auth_text_field.dart';
import 'package:voiceops/features/voice_onboarding/screens/voice_onboarding_screen.dart';
import 'package:voiceops/main.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/co_rider_voice_provider.dart';
import 'package:voiceops/providers/onboarding_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

/// A mid-range Android phone, in logical pixels.
const _phone = Size(360, 780);

void main() {
  setUpAll(disableGoogleFontsFetching);

  // The co-rider and background animate forever, so step time explicitly
  // instead of pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(KoraMotion.slow * 2);
  }

  late FakeVoiceOnboardingStore voiceOnboardingStore;
  late FakeCoRiderVoiceStore coRiderVoiceStore;
  late ProviderContainer container;

  setUp(() {
    voiceOnboardingStore = FakeVoiceOnboardingStore();
    coRiderVoiceStore = FakeCoRiderVoiceStore();
  });

  /// Boots the real app (router and auth gate included), past the
  /// pre-sign-up onboarding flow, against a fake Supabase and a fake voice
  /// socket. Onboarding_test.dart and auth_test.dart cover the flows this
  /// step sits between.
  Future<FakeAuthRepository> pumpApp(WidgetTester tester) async {
    final auth = FakeAuthRepository();
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        onboardingCompletedAtLaunchProvider.overrideWithValue(true),
        ...offlineOverrides(
          onboardingStore: FakeOnboardingStore(completed: true),
          voiceOnboardingStore: voiceOnboardingStore,
          coRiderVoiceStore: coRiderVoiceStore,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KoraApp(),
      ),
    );
    await settle(tester);
    return auth;
  }

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
    await tester.pump(KoraMotion.slow);
  }

  Future<void> signUp(WidgetTester tester) async {
    await tap(tester, find.text('Get started'));
    await enter(tester, 'Full name', 'Ada Obi');
    await enter(tester, 'Email', 'ada@voiceops.test');
    await enter(tester, 'Password', 'correct-horse');
    await enter(tester, 'Phone number', '+234 801 234 5678');
    await tap(tester, find.byType(Checkbox));
    await tap(
      tester,
      find.widgetWithText(PrimaryButton, SignUpScreen.title),
    );
  }

  testWidgets(
    'the voice step shows once right after sign-up, with the fallback '
    'voice already selected',
    (tester) async {
      final auth = await pumpApp(tester);
      await signUp(tester);

      expect(auth.lastSignUp, isNotNull);
      expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
      expect(find.byType(MainShell), findsNothing);
      expect(container.read(coRiderVoiceProvider), CoRiderVoice.fallback);

      await tap(tester, find.text('Continue'));
      expect(find.byType(VoiceOnboardingScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
      expect(voiceOnboardingStore.shown, isTrue);
    },
  );

  testWidgets('choosing a different voice and saving persists it', (
    tester,
  ) async {
    await pumpApp(tester);
    await signUp(tester);
    expect(find.byType(VoiceOnboardingScreen), findsOneWidget);

    final michael = find.byKey(const Key('voice-onboarding-option-michael'));
    await tap(tester, michael);
    // Only a draft until Save.
    expect(container.read(coRiderVoiceProvider), CoRiderVoice.anna);
    expect(coRiderVoiceStore.value, isNull);

    await tap(tester, find.text('Save'));
    expect(container.read(coRiderVoiceProvider), CoRiderVoice.michael);
    expect(find.byType(MainShell), findsOneWidget);
    expect(coRiderVoiceStore.value, CoRiderVoice.michael);

    // invalidate() only marks the provider dirty; reading its notifier
    // below is what actually rebuilds it and starts the async storage
    // load, so wait on that load before checking the reloaded state.
    container.invalidate(coRiderVoiceProvider);
    await container.read(coRiderVoiceProvider.notifier).loaded;
    await settle(tester);
    expect(container.read(coRiderVoiceProvider), CoRiderVoice.michael);
  });

  testWidgets('a device that has already shown the step never shows it '
      'again after another sign-up', (tester) async {
    voiceOnboardingStore.shown = true;
    await pumpApp(tester);
    await signUp(tester);

    expect(find.byType(VoiceOnboardingScreen), findsNothing);
    expect(find.byType(MainShell), findsOneWidget);
  });

  testWidgets(
    'a plain sign-in never shows the voice step, even with the flag unset',
    (tester) async {
      await pumpApp(tester);
      await tap(tester, find.text('Get started'));
      await tap(
        tester,
        find.text('Already have an account? Sign in', findRichText: true),
      );
      await enter(tester, 'Email', 'ada@voiceops.test');
      await enter(tester, 'Password', 'correct-horse');
      await tap(
        tester,
        find.widgetWithText(PrimaryButton, SignInScreen.title),
      );

      expect(find.byType(VoiceOnboardingScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
    },
  );
}
