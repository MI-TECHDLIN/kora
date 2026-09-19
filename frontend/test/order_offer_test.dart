import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/core/widgets/push_to_talk_button.dart';
import 'package:voiceops/features/map/screens/map_screen.dart';
import 'package:voiceops/features/settings/screens/settings_screen.dart';
import 'package:voiceops/main.dart';
import 'package:voiceops/overlays/order_offer_card.dart';
import 'package:voiceops/providers/onboarding_provider.dart';
import 'package:voiceops/providers/voice_session_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

const _offer = {
  'event': 'order_offer',
  'order_id': 'order-17',
  'area': 'Lavaca St, Austin',
  'latitude': 30.271,
  'longitude': -97.746,
  'distance_km': 0.51,
  'time_window': '3:00 PM – 5:00 PM',
  'package_count': 2,
  'expires_in_s': 75,
};

void main() {
  setUpAll(disableGoogleFontsFetching);

  late FakeVoiceConnector connector;
  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    connector = FakeVoiceConnector();
    container = ProviderContainer(
      overrides: [
        ...signedInOverrides(),
        ...offlineOverrides(connector: connector),
      ],
    );
    addTearDown(container.dispose);
    container.read(onboardingProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KoraApp(),
      ),
    );
    await tester.pump();
    await tester.pump(KoraMotion.slow);

    await container.read(voiceSessionProvider.notifier).startTalking();
    await tester.pump();
  }

  testWidgets(
    'order offer stays global and tap responses use the voice socket',
    (tester) async {
      await pumpApp(tester);
      final socket = connector.last;

      socket.emit(_offer);
      await tester.pump();
      expect(find.byType(OrderOfferCard), findsOneWidget);
      expect(find.text('Lavaca St, Austin'), findsOneWidget);
      expect(find.text('0.5 km away'), findsOneWidget);
      expect(find.text('3:00 PM – 5:00 PM'), findsOneWidget);
      expect(find.text('2 packages'), findsOneWidget);
      expect(find.text('75s'), findsOneWidget);
      // Push-to-talk stays reachable, so the driver can answer by voice too.
      expect(
        tester
            .getRect(find.byType(OrderOfferCard))
            .overlaps(tester.getRect(find.byType(PushToTalkButton))),
        isFalse,
      );

      // The offer follows the driver to every tab.
      await tester.tap(find.bySemanticsLabel('Map'));
      await tester.pump(KoraMotion.slow);
      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.byType(OrderOfferCard), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pump(KoraMotion.slow);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(OrderOfferCard), findsOneWidget);

      await tester.tap(find.byKey(const Key('accept-order')));
      await tester.pump();
      expect(socket.sentText.last, {
        'event': 'accept_order',
        'order_id': 'order-17',
      });
      expect(find.text('Responding…'), findsOneWidget);

      socket.emit({
        'event': 'order_offer_closed',
        'order_id': 'order-17',
        'outcome': 'accepted',
      });
      await tester.pump();
      expect(find.byType(OrderOfferCard), findsNothing);
      expect(
        find.text('Order accepted and added to your run.'),
        findsOneWidget,
      );

      socket.emit({..._offer, 'order_id': 'order-18'});
      await tester.pump();
      await tester.tap(find.byKey(const Key('decline-order')));
      await tester.pump();
      expect(socket.sentText.last, {
        'event': 'decline_order',
        'order_id': 'order-18',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets('a failed answer keeps the offer open to try again', (
    tester,
  ) async {
    await pumpApp(tester);
    final socket = connector.last;
    socket.emit(_offer);
    await tester.pump();

    await tester.tap(find.byKey(const Key('accept-order')));
    await tester.pump();
    expect(find.text('Responding…'), findsOneWidget);

    socket.emit({
      'event': 'error',
      'code': 'internal',
      'message': "Couldn't reach the order system. Try accepting again.",
    });
    await tester.pump();
    expect(find.byKey(const Key('voice-issue')), findsOneWidget);
    expect(find.byType(OrderOfferCard), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);

    await tester.tap(find.byKey(const Key('accept-order')));
    await tester.pump();
    expect(
      socket.sentText.where((m) => m['event'] == 'accept_order'),
      hasLength(2),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('order_offer_closed removes an expired or withdrawn offer', (
    tester,
  ) async {
    await pumpApp(tester);
    final socket = connector.last;
    socket.emit(_offer);
    await tester.pump();

    socket.emit({
      'event': 'order_offer_closed',
      'order_id': 'order-17',
      'outcome': 'expired',
    });
    await tester.pump();
    expect(find.byType(OrderOfferCard), findsNothing);
    expect(
      find.text('Offer expired and went to another driver.'),
      findsOneWidget,
    );

    socket.emit({..._offer, 'order_id': 'order-19'});
    await tester.pump();
    socket.emit({
      'event': 'order_offer_closed',
      'order_id': 'order-19',
      'outcome': 'withdrawn',
    });
    await tester.pump();
    expect(find.byType(OrderOfferCard), findsNothing);
    expect(
      find.text('Offer closed because another driver took the order.'),
      findsOneWidget,
    );
    await tester.pump(KoraMotion.notice);
    expect(find.byKey(const Key('order-offer-closed-notice')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
