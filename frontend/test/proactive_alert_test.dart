import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:voiceops/app/router.dart';
import 'package:voiceops/core/api/voiceops_api.dart' show ApiException;
import 'package:voiceops/core/realtime/voice_events.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/map/data/location_source.dart';
import 'package:voiceops/overlays/proactive_alert_card.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/location_ping_provider.dart';
import 'package:voiceops/providers/map_route_provider.dart';
import 'package:voiceops/providers/navigation_provider.dart';
import 'package:voiceops/providers/notification_preferences_provider.dart';
import 'package:voiceops/providers/proactive_alert_provider.dart';
import 'package:voiceops/providers/voice_session_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

/// A `ROUTE_DEVIATION` alert: the risk engine found a faster way round.
/// Shape from docs/contracts/interface.md §1.
Map<String, Object?> sampleRerouteAlert() => {
  'event': 'PROACTIVE_ALERT',
  'severity': 'HIGH',
  'risk_type': 'ROUTE_DEVIATION',
  'message':
      'Traffic ahead adds about 8 minutes on your current route. '
      'Want me to reroute?',
  'delivery_id': 'd-4',
  'route_suggestion': {
    'eta_minutes': 12,
    'current_eta_minutes': 20,
    'geometry': 'cqkf@{_vSzEcLfJwLjMwL',
  },
};

/// An `EXCESSIVE_IDLE` alert: no route to offer, just a sentence.
Map<String, Object?> sampleIdleAlert() => {
  'event': 'PROACTIVE_ALERT',
  'severity': 'MEDIUM',
  'risk_type': 'EXCESSIVE_IDLE',
  'message': 'Driver has been stationary for over 5 minutes.',
  'delivery_id': null,
};

/// Records agent navigation instead of driving a real router.
class _FakeNavigation implements NavigationActions {
  @override
  void navigateForAgent(String screenKey) {}

  @override
  void goTo(MainTab tab) {}
}

void main() {
  // AppLifecycleListener (in LocationPinger) needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(disableGoogleFontsFetching);

  group('PROACTIVE_ALERT parsing', () {
    test(
      'a reroute alert carries the message, the ETAs and a drawable route',
      () {
        final event = VoiceEvent.parse(sampleRerouteAlert());

        expect(event, isA<ProactiveAlertEvent>());
        final alert = event! as ProactiveAlertEvent;
        expect(alert.severity, RiskSeverity.high);
        expect(alert.riskType, RiskType.routeDeviation);
        expect(alert.deliveryId, 'd-4');
        expect(alert.message, contains('adds about 8 minutes'));

        final suggestion = alert.routeSuggestion!;
        expect(suggestion.etaMinutes, 12);
        expect(suggestion.currentEtaMinutes, 20);
        expect(suggestion.savingsMinutes, 8);
        // The geometry goes through the same decoder as a map_route polyline.
        expect(suggestion.route.line, isNotEmpty);
        expect(suggestion.route.deliveryId, 'd-4');
        expect(suggestion.route.etaLabel, '12 min');
      },
    );

    test('an idle alert has no route suggestion at all', () {
      final alert = VoiceEvent.parse(sampleIdleAlert())! as ProactiveAlertEvent;

      expect(alert.riskType, RiskType.excessiveIdle);
      expect(alert.severity, RiskSeverity.medium);
      expect(alert.deliveryId, isNull);
      expect(alert.routeSuggestion, isNull);
    });

    test(
      'an explicitly null route_suggestion is the same as an absent one',
      () {
        final alert =
            VoiceEvent.parse({
                  ...sampleIdleAlert(),
                  'risk_type': 'TIME_WINDOW_RISK',
                  'route_suggestion': null,
                })!
                as ProactiveAlertEvent;

        expect(alert.riskType, RiskType.timeWindowRisk);
        expect(alert.routeSuggestion, isNull);
      },
    );

    test('an unreadable geometry still shows the alert, with no line', () {
      final alert =
          VoiceEvent.parse({
                ...sampleRerouteAlert(),
                'route_suggestion': {
                  'eta_minutes': 12,
                  'current_eta_minutes': 20,
                  // What the backend sends today: a stringified point list,
                  // not an encoded polyline.
                  'geometry': "[{'latitude': 30.2, 'longitude': -97.7}]",
                },
              })!
              as ProactiveAlertEvent;

      expect(alert.routeSuggestion!.route.line, isEmpty);
      expect(alert.routeSuggestion!.savingsMinutes, 8);
    });

    test('a route suggestion with nothing usable in it reads as none', () {
      final alert =
          VoiceEvent.parse({
                ...sampleRerouteAlert(),
                'route_suggestion': {'geometry': ''},
              })!
              as ProactiveAlertEvent;

      expect(alert.routeSuggestion, isNull);
    });

    test('an unknown risk type or severity still reaches the driver', () {
      final alert =
          VoiceEvent.parse({
                ...sampleIdleAlert(),
                'risk_type': 'METEOR_STRIKE',
                'severity': 'APOCALYPTIC',
              })!
              as ProactiveAlertEvent;

      expect(alert.riskType, RiskType.unknown);
      expect(alert.severity, RiskSeverity.medium);
      expect(alert.message, isNotEmpty);
    });

    test('an alert with no message is malformed', () {
      expect(
        () => VoiceEvent.parse({
          'event': 'PROACTIVE_ALERT',
          'severity': 'HIGH',
          'risk_type': 'ROUTE_DEVIATION',
        }),
        throwsFormatException,
      );
    });

    test('a slower "alternate" claims no savings', () {
      final alert =
          VoiceEvent.parse({
                ...sampleRerouteAlert(),
                'route_suggestion': {
                  'eta_minutes': 20,
                  'current_eta_minutes': 12,
                  'geometry': 'cqkf@{_vSzEcLfJwLjMwL',
                },
              })!
              as ProactiveAlertEvent;

      expect(alert.routeSuggestion!.savingsMinutes, isNull);
    });
  });

  group('the session', () {
    late FakeVoiceConnector connector;
    late FakeRecorder recorder;
    late FakeKoraApi api;
    late FakeAuthRepository auth;
    late FakeLocationSource location;
    late ProviderContainer container;

    setUp(() {
      connector = FakeVoiceConnector();
      recorder = FakeRecorder();
      api = FakeKoraApi();
      auth = FakeAuthRepository(signedIn: true);
      location = FakeLocationSource();
    });

    void onFakeTime(
      void Function(FakeAsync async, void Function() flush) body,
    ) {
      fakeAsync((async) {
        container = ProviderContainer(
          overrides: [
            ...offlineOverrides(
              connector: connector,
              recorder: recorder,
              api: api,
              location: location,
            ),
            authRepositoryProvider.overrideWithValue(auth),
            navigationProvider.overrideWithValue(_FakeNavigation()),
          ],
        );
        container.read(notificationPreferencesProvider);
        async.flushMicrotasks();
        body(async, async.flushMicrotasks);
        container.dispose();
        async.flushMicrotasks();
      });
    }

    VoiceSession session() => container.read(voiceSessionProvider.notifier);

    test('a reroute alert is shown and its route is drawn on the map', () {
      onFakeTime((async, flush) {
        session().onPushToTalk();
        flush();
        final focusBefore = container.read(mapFocusProvider).serial;

        connector.last.emit(sampleRerouteAlert());
        flush();

        final alert = container.read(proactiveAlertProvider)!;
        expect(alert.riskType, RiskType.routeDeviation);
        expect(container.read(mapRouteProvider)!.line, isNotEmpty);
        expect(container.read(mapRouteProvider)!.summary, 'Suggested reroute');
        expect(container.read(mapFocusProvider).serial, focusBefore + 1);
        expect(container.read(mapFocusProvider).target, MapFocusTarget.route);

        // It clears itself: the driver answers by voice, not by tapping.
        async.elapse(KoraMotion.proactiveAlert);
        flush();
        expect(container.read(proactiveAlertProvider), isNull);
        // The suggested line stays drawn; only the notice times out.
        expect(container.read(mapRouteProvider), isNotNull);
      });
    });

    test('an alert with no route leaves the map alone', () {
      onFakeTime((async, flush) {
        session().onPushToTalk();
        flush();

        connector.last.emit(sampleIdleAlert());
        flush();

        expect(container.read(proactiveAlertProvider), isNotNull);
        expect(container.read(mapRouteProvider), isNull);
        expect(container.read(mapFocusProvider).serial, 0);

        container.read(proactiveAlertProvider.notifier).dismiss();
        expect(container.read(proactiveAlertProvider), isNull);
      });
    });

    test('an undrawable geometry leaves the map alone too', () {
      onFakeTime((async, flush) {
        session().onPushToTalk();
        flush();

        connector.last.emit({
          ...sampleRerouteAlert(),
          'route_suggestion': {'eta_minutes': 12, 'current_eta_minutes': 20},
        });
        flush();

        expect(container.read(proactiveAlertProvider), isNotNull);
        expect(container.read(mapRouteProvider), isNull);
        container.read(proactiveAlertProvider.notifier).dismiss();
      });
    });

    test('a newer alert replaces an older one', () {
      onFakeTime((async, flush) {
        session().onPushToTalk();
        flush();

        connector.last
          ..emit(sampleIdleAlert())
          ..emit(sampleRerouteAlert());
        flush();

        expect(
          container.read(proactiveAlertProvider)!.riskType,
          RiskType.routeDeviation,
        );
        container.read(proactiveAlertProvider.notifier).dismiss();
      });
    });

    test('signing out clears a visible alert', () {
      onFakeTime((async, flush) {
        session().onPushToTalk();
        flush();
        connector.last.emit(sampleIdleAlert());
        flush();
        expect(container.read(proactiveAlertProvider), isNotNull);

        session().disconnect();
        flush();
        expect(container.read(proactiveAlertProvider), isNull);
      });
    });

    test('a disabled proactive alert does not show or replace the route', () {
      onFakeTime((async, flush) {
        container
            .read(notificationPreferencesProvider.notifier)
            .setProactiveAlerts(enabled: false);
        flush();
        session().onPushToTalk();
        flush();

        connector.last.emit(sampleRerouteAlert());
        flush();

        expect(container.read(proactiveAlertProvider), isNull);
        expect(container.read(mapRouteProvider), isNull);
      });
    });
  });

  group('the GPS ping loop', () {
    late FakeVoiceConnector connector;
    late FakeRecorder recorder;
    late FakeKoraApi api;
    late FakeAuthRepository auth;
    late FakeLocationSource location;
    late ProviderContainer container;

    setUp(() {
      connector = FakeVoiceConnector();
      recorder = FakeRecorder();
      api = FakeKoraApi();
      auth = FakeAuthRepository(signedIn: true);
      location = FakeLocationSource();
    });

    /// Downtown Austin, the demo area: 10 m/s ≈ 36 km/h.
    LocationFix fix({double speed = 10}) => LocationFix(
      const LatLng(30.2672, -97.7431),
      heading: 91,
      speed: speed,
      accuracy: 7.5,
    );

    void onFakeTime(
      void Function(FakeAsync async, void Function() flush) body,
    ) {
      fakeAsync((async) {
        container = ProviderContainer(
          overrides: [
            ...offlineOverrides(
              connector: connector,
              recorder: recorder,
              api: api,
              location: location,
            ),
            authRepositoryProvider.overrideWithValue(auth),
            navigationProvider.overrideWithValue(_FakeNavigation()),
          ],
        );
        body(async, async.flushMicrotasks);
        container.dispose();
        async.flushMicrotasks();
      });
    }

    LocationPinger pinger() => container.read(locationPingerProvider);
    VoiceSession session() => container.read(voiceSessionProvider.notifier);

    test('pings on the interval while the session is up, then stops', () {
      onFakeTime((async, flush) {
        pinger();
        location.emit(fix());
        flush();
        // Nothing to report until the driver is actually on a shift.
        expect(pinger().isPinging, isFalse);
        expect(api.pings, isEmpty);

        session().onPushToTalk();
        flush();
        expect(pinger().isPinging, isTrue);
        // The first ping goes at once, not an interval later.
        expect(api.pings, hasLength(1));

        async.elapse(locationPingInterval * 3);
        flush();
        expect(api.pings, hasLength(4));

        session().disconnect();
        flush();
        expect(pinger().isPinging, isFalse);

        async.elapse(locationPingInterval * 5);
        flush();
        expect(api.pings, hasLength(4));
      });
    });

    test('the ping carries the fix in the units the backend validates', () {
      onFakeTime((async, flush) {
        pinger();
        location.emit(fix());
        session().onPushToTalk();
        flush();

        final ping = api.pings.single;
        expect(ping.latitude, closeTo(30.2672, 1e-9));
        expect(ping.longitude, closeTo(-97.7431, 1e-9));
        // geolocator reports m/s; LocationPingRequest wants km/h.
        expect(ping.speedKmh, closeTo(36, 1e-9));
        expect(ping.heading, 91);
        expect(ping.accuracyMetres, 7.5);
        expect(ping.shiftId, 'shift-1');
        expect(ping.toJson()['speed'], closeTo(36, 1e-9));

        session().disconnect();
        flush();
      });
    });

    test('a backgrounded app stops pinging and resumes when it comes back', () {
      onFakeTime((async, flush) {
        pinger();
        location.emit(fix());
        session().onPushToTalk();
        flush();
        expect(api.pings, hasLength(1));

        pinger().setForeground(false);
        expect(pinger().isPinging, isFalse);
        async.elapse(locationPingInterval * 3);
        flush();
        expect(api.pings, hasLength(1));

        pinger().setForeground(true);
        flush();
        expect(pinger().isPinging, isTrue);
        expect(api.pings, hasLength(2));

        session().disconnect();
        flush();
      });
    });

    test(
      'a failed ping is dropped, never retried, and never stops the loop',
      () {
        onFakeTime((async, flush) {
          api.pingFailure = const ApiException('offline');
          pinger();
          location.emit(fix());
          session().onPushToTalk();
          flush();
          expect(api.pings, hasLength(1));

          async.elapse(locationPingInterval);
          flush();
          expect(api.pings, hasLength(2));
          // Nothing about a dropped ping reaches the driver.
          expect(container.read(voiceSessionProvider).issue, isNull);

          session().disconnect();
          flush();
        });
      },
    );

    test('the loop waits for a fix before it starts ticking', () {
      onFakeTime((async, flush) {
        pinger();
        session().onPushToTalk();
        flush();
        expect(pinger().isPinging, isFalse);

        async.elapse(locationPingInterval * 2);
        flush();
        expect(api.pings, isEmpty);

        location.emit(fix(speed: 0));
        flush();
        expect(pinger().isPinging, isTrue);
        expect(api.pings.single.speedKmh, 0);

        session().disconnect();
        flush();
      });
    });
  });

  group('the alert card', () {
    Future<ProviderContainer> pumpCard(
      WidgetTester tester,
      Map<String, Object?> event,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(proactiveAlertProvider.notifier)
          .show(VoiceEvent.parse(event)! as ProactiveAlertEvent);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: ProactiveAlertCard())),
          ),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('a reroute alert shows the sentence and the time saved', (
      tester,
    ) async {
      final container = await pumpCard(tester, sampleRerouteAlert());

      expect(find.byKey(const Key('proactive-alert')), findsOneWidget);
      expect(find.textContaining('Want me to reroute?'), findsOneWidget);
      expect(find.text('FASTER ROUTE'), findsOneWidget);
      // The comparison is the decision: 20 minutes becomes 12.
      expect(find.byKey(const Key('proactive-alert-eta')), findsOneWidget);
      expect(find.text('20 min'), findsOneWidget);
      expect(find.text('12 min'), findsOneWidget);
      expect(find.text('- saves 8 min'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Dismiss'));
      await tester.pump();
      expect(container.read(proactiveAlertProvider), isNull);
      expect(find.byKey(const Key('proactive-alert')), findsNothing);
    });

    testWidgets('an alert with no route shows the message alone', (
      tester,
    ) async {
      await pumpCard(tester, sampleIdleAlert());

      expect(find.byKey(const Key('proactive-alert')), findsOneWidget);
      expect(
        find.textContaining('stationary for over 5 minutes'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('proactive-alert-eta')), findsNothing);

      // It clears itself rather than sitting over the map.
      await tester.pump(KoraMotion.proactiveAlert);
      expect(find.byKey(const Key('proactive-alert')), findsNothing);
    });

    testWidgets('the mic-hot lime never appears on an alert', (tester) async {
      await pumpCard(tester, sampleRerouteAlert());

      final colours = [
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          text.style?.color,
        for (final icon in tester.widgetList<Icon>(find.byType(Icon)))
          icon.color,
      ];
      expect(colours, isNot(contains(KoraColors.live)));

      await tester.pump(KoraMotion.proactiveAlert);
    });
  });
}
