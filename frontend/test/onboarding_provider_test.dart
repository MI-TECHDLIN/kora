import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceops/providers/onboarding_provider.dart';

/// A fresh container as main.dart builds one on launch: the saved flag is
/// read first, then handed to the providers.
Future<ProviderContainer> launch() async {
  final completed = await loadOnboardingCompleted(
    const SharedPreferencesOnboardingStore(),
  );
  final container = ProviderContainer(
    overrides: [
      onboardingCompletedAtLaunchProvider.overrideWithValue(completed),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _BrokenStore implements OnboardingStore {
  @override
  Future<bool> load() => Future.error(StateError('no storage'));

  @override
  Future<void> save({required bool completed}) =>
      Future.error(StateError('no storage'));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a first launch shows onboarding', () async {
    final container = await launch();
    expect(container.read(onboardingProvider), isTrue);
  });

  test('completed onboarding stays completed after a restart', () async {
    final first = await launch();
    first.read(onboardingProvider.notifier).complete();
    expect(first.read(onboardingProvider), isFalse);
    await pumpEventQueue();
    first.dispose();

    final second = await launch();
    expect(second.read(onboardingProvider), isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'has_completed_onboarding',
      ),
      isTrue,
    );
  });

  test('reset shows onboarding again, on the next launch too', () async {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    final first = await launch();
    expect(first.read(onboardingProvider), isFalse);
    first.read(onboardingProvider.notifier).reset();
    expect(first.read(onboardingProvider), isTrue);
    await pumpEventQueue();
    first.dispose();

    final second = await launch();
    expect(second.read(onboardingProvider), isTrue);
  });

  test('unreadable storage shows onboarding; a failed save keeps the '
      'state for this run', () async {
    expect(await loadOnboardingCompleted(_BrokenStore()), isFalse);

    final container = ProviderContainer(
      overrides: [onboardingStoreProvider.overrideWithValue(_BrokenStore())],
    );
    addTearDown(container.dispose);
    container.read(onboardingProvider.notifier).complete();
    await pumpEventQueue();
    expect(container.read(onboardingProvider), isFalse);
  });
}
