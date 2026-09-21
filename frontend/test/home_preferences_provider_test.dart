import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voiceops/providers/home_preferences_provider.dart';

void main() {
  const store = SharedPreferencesHomePreferencesStore();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'optional Home features default off when no preference exists',
    () async {
      final preferences = await store.load();

      expect(preferences.quickActionsEnabled, isFalse);
      expect(preferences.conversationEnabled, isFalse);
      expect(preferences.locationEnabled, isFalse);
    },
  );

  test('optional Home feature choices persist independently', () async {
    await store.saveQuickActions(enabled: true);
    await store.saveConversation(enabled: true);
    await store.saveLocation(enabled: true);

    var preferences = await store.load();
    expect(preferences.quickActionsEnabled, isTrue);
    expect(preferences.conversationEnabled, isTrue);
    expect(preferences.locationEnabled, isTrue);

    await store.saveConversation(enabled: false);
    preferences = await store.load();
    expect(preferences.quickActionsEnabled, isTrue);
    expect(preferences.conversationEnabled, isFalse);
    expect(preferences.locationEnabled, isTrue);
  });
}
