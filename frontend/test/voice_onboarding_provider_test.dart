import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/voice_onboarding_provider.dart';

import 'fake_auth.dart';

class _BrokenStore implements VoiceOnboardingStore {
  @override
  Future<bool> load() => Future.error(StateError('no storage'));

  @override
  Future<void> save({required bool shown}) =>
      Future.error(StateError('no storage'));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository());

  ProviderContainer container({List<Override> overrides = const []}) {
    final c = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        ...overrides,
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('never shows on its own, even before anything asks', () {
    final c = container();
    expect(c.read(voiceOnboardingProvider), isFalse);
  });

  test('a device that has never shown it shows once asked', () async {
    final c = container();
    await c.read(voiceOnboardingProvider.notifier).showIfNeverShown();
    expect(c.read(voiceOnboardingProvider), isTrue);
  });

  test(
    'a device that already shows it stays hidden, even if asked again',
    () async {
      SharedPreferences.setMockInitialValues({
        'has_shown_voice_onboarding': true,
      });
      final c = container();
      await c.read(voiceOnboardingProvider.notifier).showIfNeverShown();
      expect(c.read(voiceOnboardingProvider), isFalse);
    },
  );

  test(
    'completing persists the flag so a later launch never shows it again',
    () async {
      final first = container();
      await first.read(voiceOnboardingProvider.notifier).showIfNeverShown();
      expect(first.read(voiceOnboardingProvider), isTrue);

      first.read(voiceOnboardingProvider.notifier).complete();
      expect(first.read(voiceOnboardingProvider), isFalse);
      await pumpEventQueue();
      first.dispose();

      expect(
        (await SharedPreferences.getInstance()).getBool(
          'has_shown_voice_onboarding',
        ),
        isTrue,
      );
      final second = container();
      await second.read(voiceOnboardingProvider.notifier).showIfNeverShown();
      expect(second.read(voiceOnboardingProvider), isFalse);
    },
  );

  test(
    'unreadable storage still shows the step once; a failed save keeps '
    'that only for this run',
    () async {
      final c = container(
        overrides: [
          voiceOnboardingStoreProvider.overrideWithValue(_BrokenStore()),
        ],
      );
      await c.read(voiceOnboardingProvider.notifier).showIfNeverShown();
      expect(c.read(voiceOnboardingProvider), isTrue);

      c.read(voiceOnboardingProvider.notifier).complete();
      await pumpEventQueue();
      expect(c.read(voiceOnboardingProvider), isFalse);
    },
  );

  test(
    'a sign-out before completing the step clears it, so the next '
    'sign-in never inherits it',
    () async {
      final c = container();
      await c.read(voiceOnboardingProvider.notifier).showIfNeverShown();
      expect(c.read(voiceOnboardingProvider), isTrue);

      // The driver backs out before tapping Continue: nothing was ever
      // persisted, so the in-memory flag is the only thing keeping it on.
      auth.signOut();
      await pumpEventQueue();
      expect(c.read(voiceOnboardingProvider), isFalse);

      // A plain sign-in afterwards must not resurrect it.
      auth.completeSignIn();
      await pumpEventQueue();
      expect(c.read(voiceOnboardingProvider), isFalse);
    },
  );
}
