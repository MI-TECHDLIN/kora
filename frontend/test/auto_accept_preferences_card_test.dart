import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/settings/screens/settings_screen.dart';
import 'package:voiceops/features/settings/widgets/auto_accept_preferences_card.dart';

import 'fake_voice.dart';
import 'test_fonts.dart';

/// The Settings auto-accept card is the one surface a driver can see and
/// override whatever a voice command configured — the captain's "remains in
/// control" requirement (AGENTS.md). These tests drive it the way a driver
/// would and check it reads/writes the real `driver_preferences` keys
/// (`FakeKoraApi.preferences`), the same keys `app/agents/tools/preferences.py`
/// writes for a spoken command.
void main() {
  setUpAll(disableGoogleFontsFetching);

  late FakeKoraApi api;
  late ProviderContainer container;

  setUp(() {
    api = FakeKoraApi();
  });

  /// Pumps the card alone (not the whole scrollable Settings screen, which
  /// this section sits well below the fold of at phone height).
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [koraApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildKoraTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: AutoAcceptPreferencesCard()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(); // lets the initial preferences reload land
  }

  testWidgets('off by default, and the editors stay hidden until enabled', (
    tester,
  ) async {
    await pump(tester);

    final toggle = tester.widget<Switch>(
      find.byKey(const Key('auto-accept-toggle')),
    );
    expect(toggle.value, isFalse);
    expect(find.text('Max pickup distance'), findsNothing);
    expect(find.text('Preferred & avoided areas'), findsNothing);
    expect(find.text('Order types'), findsNothing);
  });

  testWidgets('flipping the switch writes auto_accept_orders and reveals the editors', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('auto-accept-toggle')));
    await tester.pump();

    expect(api.preferenceWrites, [('auto_accept_orders', 'true')]);
    expect(find.text('Max pickup distance'), findsOneWidget);
    expect(find.text('Preferred & avoided areas'), findsOneWidget);
    expect(find.text('Order types'), findsOneWidget);
  });

  testWidgets('a driver who already turned it on by voice sees it on here too', (
    tester,
  ) async {
    api.preferences['auto_accept_orders'] = 'true';
    await pump(tester);

    final toggle = tester.widget<Switch>(
      find.byKey(const Key('auto-accept-toggle')),
    );
    expect(toggle.value, isTrue);
    expect(find.text('Max pickup distance'), findsOneWidget);
  });

  testWidgets('entering a max distance writes max_order_distance_km on submit', (
    tester,
  ) async {
    api.preferences['auto_accept_orders'] = 'true';
    await pump(tester);

    await tester.enterText(find.byType(TextFormField).first, '2.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(api.preferenceWrites, [('max_order_distance_km', '2.5')]);
  });

  testWidgets('adding an avoided area writes it into geographic_zones', (
    tester,
  ) async {
    api.preferences['auto_accept_orders'] = 'true';
    await pump(tester);

    await tester.tap(find.byKey(const Key('add-zone-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('zone-name-field')),
      'East Riverside',
    );
    await tester.enterText(find.byKey(const Key('zone-radius-field')), '1.5');
    await tester.tap(find.byKey(const Key('zone-type-avoided')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('zone-save-button')));
    await tester.pumpAndSettle();

    final stored = api.preferences['geographic_zones'];
    expect(stored, contains('"name":"East Riverside"'));
    expect(stored, contains('"zone_type":"avoided"'));
    expect(find.text('East Riverside · 1.5 km'), findsOneWidget);
  });

  testWidgets('adding an order type writes it into order_type_prefs', (
    tester,
  ) async {
    api.preferences['auto_accept_orders'] = 'true';
    await pump(tester);

    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('category-name-field')),
      'Food',
    );
    await tester.tap(find.byKey(const Key('category-save-button')));
    await tester.pumpAndSettle();

    expect(api.preferences['order_type_prefs'], '{"accepted_categories":["Food"]}');
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('removing a category clears order_type_prefs', (tester) async {
    api.preferences['auto_accept_orders'] = 'true';
    api.preferences['order_type_prefs'] = '{"accepted_categories":["Food"]}';
    await pump(tester);

    expect(find.text('Food'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove-Food')));
    await tester.pump();

    expect(api.preferences.containsKey('order_type_prefs'), isFalse);
    expect(find.text('Food'), findsNothing);
  });

  testWidgets('the card is wired into the real Settings screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [koraApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildKoraTheme(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('auto-accept-preferences')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('auto-accept-toggle')),
      200,
    );
    expect(find.byKey(const Key('auto-accept-toggle')), findsOneWidget);
  });
}
