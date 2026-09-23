import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/app/router.dart';
import 'package:voiceops/core/api/voiceops_api.dart' show ApiException;
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/settings/screens/settings_screen.dart';
import 'package:voiceops/features/summary/screens/summary_screen.dart';
import 'package:voiceops/features/voice/screens/voice_screen.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/navigation_provider.dart';
import 'package:voiceops/providers/order_queue_provider.dart';
import 'package:voiceops/providers/queue_focus_provider.dart';
import 'package:voiceops/providers/shift_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'order_queue_fixtures.dart';
import 'test_fonts.dart';

/// Records where Home sends the driver instead of driving a real router.
class _FakeNavigation implements NavigationActions {
  final tabs = <MainTab>[];

  @override
  void goTo(MainTab tab) => tabs.add(tab);

  @override
  void navigateForAgent(String screenKey) {}
}

void main() {
  setUpAll(disableGoogleFontsFetching);

  late FakeHomePreferencesStore homePreferencesStore;
  late FakeKoraApi api;
  late _FakeNavigation navigation;
  late ProviderContainer container;

  setUp(() {
    homePreferencesStore = FakeHomePreferencesStore();
    api = FakeKoraApi();
    navigation = _FakeNavigation();
  });

  ProviderContainer build() {
    container = ProviderContainer(
      overrides: [
        ...offlineOverrides(
          api: api,
          homePreferencesStore: homePreferencesStore,
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
        navigationProvider.overrideWithValue(navigation),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildKoraTheme(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> startShift(WidgetTester tester) async {
    await container.read(shiftProvider.notifier).ensureStarted();
    await tester.pump();
    await tester.pump();
  }

  Finder key(String value) => find.byKey(Key(value));

  testWidgets('with nothing queued Home shows neither card', (tester) async {
    build();
    await pumpScreen(tester, const VoiceScreen());

    expect(key('next-orders-card'), findsNothing);
    expect(key('target-indicator'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a backend without a queue leaves Home as it was', (
    tester,
  ) async {
    api.queueFailure = const ApiException('Not Found', statusCode: 404);
    build();
    await pumpScreen(tester, const VoiceScreen());
    await startShift(tester);

    expect(key('next-orders-card'), findsNothing);
    expect(key('target-indicator'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Next Orders shows the current order and the next three', (
    tester,
  ) async {
    api.queue = queueOf(8, completed: 2, target: 15);
    build();
    await pumpScreen(tester, const VoiceScreen());
    await startShift(tester);

    expect(key('next-orders-card'), findsOneWidget);
    expect(find.text('Recipient 3 · now'), findsOneWidget);
    expect(key('next-order-d-3'), findsOneWidget);
    expect(key('next-order-d-4'), findsOneWidget);
    expect(key('next-order-d-5'), findsOneWidget);
    expect(key('next-order-d-6'), findsOneWidget);
    // Completed and further-out orders stay off Home.
    expect(key('next-order-d-1'), findsNothing);
    expect(key('next-order-d-7'), findsNothing);
    expect(find.text('+ 2 more'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the target indicator reads "8 / 15 deliveries"', (tester) async {
    api.queue = queueOf(10, completed: 8, target: 15);
    build();
    await pumpScreen(tester, const VoiceScreen());
    await startShift(tester);

    expect(find.text('8 / 15 deliveries'), findsOneWidget);
  });

  testWidgets('both cards fit a small phone', (tester) async {
    api.queue = queueOf(8, completed: 2, target: 150);
    build();
    await pumpScreen(tester, const VoiceScreen());
    tester.view.physicalSize = const Size(320, 568);
    await startShift(tester);

    expect(key('next-orders-card'), findsOneWidget);
    expect(find.text('2 / 150 deliveries'), findsOneWidget);
    expect(tester.takeException()?.toString(), isNull);
  });

  testWidgets('a target with no shift still shows on Home', (tester) async {
    api.preferences[dailyDeliveryTargetKey] = '10';
    build();
    await pumpScreen(tester, const VoiceScreen());

    expect(find.text('0 / 10 deliveries'), findsOneWidget);
    expect(key('next-orders-card'), findsNothing);
  });

  testWidgets('Home follows the queue when an order changes anywhere', (
    tester,
  ) async {
    api.queue = queueOf(4, completed: 1, target: 3);
    build();
    await pumpScreen(tester, const VoiceScreen());
    await startShift(tester);
    expect(find.text('Recipient 2 · now'), findsOneWidget);
    expect(find.text('1 / 3 deliveries'), findsOneWidget);

    container
        .read(orderQueueProvider.notifier)
        .apply(queueOf(4, completed: 2, target: 3));
    await tester.pump();

    expect(find.text('Recipient 3 · now'), findsOneWidget);
    expect(find.text('Recipient 2 · now'), findsNothing);
    expect(find.text('2 / 3 deliveries'), findsOneWidget);
  });

  testWidgets('tapping Next Orders opens the full queue on Summary', (
    tester,
  ) async {
    api.queue = queueOf(4);
    build();
    await pumpScreen(tester, const VoiceScreen());
    await startShift(tester);

    await tester.ensureVisible(key('next-orders-card'));
    await tester.pump();
    await tester.tap(key('next-orders-card'));
    await tester.pump();

    expect(navigation.tabs, [MainTab.summary]);
    expect(container.read(queueFocusRequestProvider), isTrue);
  });

  testWidgets('tapping the target indicator opens Summary', (tester) async {
    api.queue = queueOf(4, target: 5);
    build();
    await pumpScreen(tester, const VoiceScreen());
    await startShift(tester);

    await tester.tap(key('target-indicator'));
    await tester.pump();

    expect(navigation.tabs, [MainTab.summary]);
  });

  testWidgets('Summary lands on the queue after Home asks for it', (
    tester,
  ) async {
    api.queue = queueOf(8);
    build();
    await startShift(tester);
    // Home asked before the Summary tab was ever built.
    container.read(queueFocusRequestProvider.notifier).state = true;

    await pumpScreen(tester, const SummaryScreen());
    await tester.pump(KoraMotion.slow * 2);

    expect(container.read(queueFocusRequestProvider), isFalse);
    expect(tester.getTopLeft(key('order-queue')).dy, lessThan(120));
  });

  testWidgets('both cards are on by default and Settings hides each', (
    tester,
  ) async {
    api.queue = queueOf(4, target: 5);
    build();
    await pumpScreen(tester, const SettingsScreen());

    Switch switchOf(String toggle) => tester.widget<Switch>(
      find.descendant(of: key(toggle), matching: find.byType(Switch)),
    );
    expect(switchOf('next-orders-toggle').value, isTrue);
    expect(switchOf('target-toggle').value, isTrue);

    await tester.tap(
      find.descendant(
        of: key('next-orders-toggle'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    expect(homePreferencesStore.value.nextOrdersEnabled, isFalse);

    await pumpScreen(tester, const VoiceScreen());
    await startShift(tester);
    expect(key('next-orders-card'), findsNothing);
    expect(key('target-indicator'), findsOneWidget);

    await pumpScreen(tester, const SettingsScreen());
    await tester.tap(
      find.descendant(of: key('target-toggle'), matching: find.byType(Switch)),
    );
    await tester.pump();
    expect(homePreferencesStore.value.targetEnabled, isFalse);

    await pumpScreen(tester, const VoiceScreen());
    expect(key('next-orders-card'), findsNothing);
    expect(key('target-indicator'), findsNothing);

    await pumpScreen(tester, const SettingsScreen());
    for (final toggle in ['next-orders-toggle', 'target-toggle']) {
      await tester.tap(
        find.descendant(of: key(toggle), matching: find.byType(Switch)),
      );
    }
    await tester.pump();
    await pumpScreen(tester, const VoiceScreen());
    expect(key('next-orders-card'), findsOneWidget);
    expect(key('target-indicator'), findsOneWidget);
  });

  testWidgets('saved choices come back when Home is rebuilt', (tester) async {
    homePreferencesStore.value = homePreferencesStore.value.copyWith(
      nextOrdersEnabled: false,
      targetEnabled: false,
    );
    api.queue = queueOf(4, target: 5);
    build();
    await pumpScreen(tester, const VoiceScreen());
    await startShift(tester);

    expect(key('next-orders-card'), findsNothing);
    expect(key('target-indicator'), findsNothing);
  });
}
