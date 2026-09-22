import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceops/providers/wake_word_provider.dart';

void main() {
  const store = SharedPreferencesWakeWordStore();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('wake word defaults on and persists the Settings choice', () async {
    expect(await store.load(), isTrue);

    await store.save(enabled: false);
    expect(await store.load(), isFalse);

    await store.save(enabled: true);
    expect(await store.load(), isTrue);
  });

  test('controller restores the persisted wake-word choice', () async {
    await store.save(enabled: false);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(wakeWordEnabledProvider), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(wakeWordEnabledProvider), isFalse);
  });
}
