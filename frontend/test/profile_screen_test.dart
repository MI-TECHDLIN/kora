import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voiceops/app/main_shell.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/auth/screens/welcome_screen.dart';
import 'package:voiceops/features/profile/screens/profile_screen.dart';
import 'package:voiceops/features/voice/screens/voice_screen.dart';
import 'package:voiceops/main.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/onboarding_provider.dart';
import 'package:voiceops/providers/shift_provider.dart';
import 'package:voiceops/providers/voice_session_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

const _phone = '+15125550100';

void main() {
  setUpAll(disableGoogleFontsFetching);

  // The co-rider and background animate forever: step time, never settle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(KoraMotion.slow * 2);
  }

  late FakeKoraApi api;
  late FakeCompanyConnectionStore connections;

  setUp(() {
    api = FakeKoraApi(
      profile: DriverProfile(
        id: 'driver-1',
        name: 'Ada Obi',
        vehicleType: 'Motorbike',
        phone: _phone,
        createdAt: DateTime(2026, 9, 3, 12),
      ),
    );
    connections = FakeCompanyConnectionStore();
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...signedInOverrides(),
          ...offlineOverrides(api: api, companyConnectionStore: connections),
        ],
        child: MaterialApp(
          theme: buildKoraTheme(),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
  }

  Finder field(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextFormField),
  );

  // enterText doesn't rebuild; pump so the buttons see the new text.
  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.enterText(field(key), text);
    await tester.pump();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the top-right icon on the voice screen opens the profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        ...signedInOverrides(),
        ...offlineOverrides(api: api),
      ],
    );
    addTearDown(container.dispose);
    container.read(onboardingProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const KoraApp()),
    );
    await settle(tester);
    expect(find.byType(VoiceScreen), findsOneWidget);

    // Top-right corner, above the voice screen's content, not in the nav.
    final button = find.byKey(const Key('profile-button'));
    final rect = tester.getRect(button);
    expect(rect.right, greaterThan(360 * 0.8));
    expect(rect.top, lessThan(100));
    expect(
      find.descendant(of: find.byType(MainShell), matching: button),
      findsOneWidget,
    );

    await tester.tap(button);
    await settle(tester);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Ada Obi'), findsWidgets);

    await tester.tap(find.byKey(const Key('profile-back')));
    await settle(tester);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.byType(VoiceScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a restored session waits for ensure-profile before the first profile load',
    (tester) async {
      final ensureGate = Completer<void>();
      api
        ..ensureProfileGate = ensureGate
        ..profileRequiresEnsure = true;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          ...signedInOverrides(),
          ...offlineOverrides(api: api),
        ],
      );
      addTearDown(container.dispose);
      container.read(onboardingProvider.notifier).complete();
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const KoraApp()),
      );
      await settle(tester);

      // Map warm-up watches the same profile provider before the Profile
      // screen is opened. It must not race GET /profile ahead of the
      // restored session's POST /ensure-profile.
      expect(api.ensureProfileCalls, 1);
      expect(api.profileCalls, 0);

      // Summary does not render profile details itself, but it lives under
      // the same global map warm-up. Visiting it while ensure-profile is in
      // flight must not let that shared profile read jump the gate either.
      await tester.tap(find.bySemanticsLabel('Summary'));
      await settle(tester);
      expect(find.text('Your shift summary'), findsOneWidget);
      expect(api.profileCalls, 0);
      await tester.tap(find.bySemanticsLabel('Voice'));
      await settle(tester);

      await tester.tap(find.byKey(const Key('profile-button')));
      await settle(tester);
      expect(find.byKey(const Key('profile-loading')), findsOneWidget);
      expect(find.byKey(const Key('profile-error')), findsNothing);
      expect(api.profileCalls, 0);

      ensureGate.complete();
      await settle(tester);
      expect(api.profileCalls, 1);
      expect(find.byKey(const Key('profile-error')), findsNothing);
      expect(field('profile-name'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'sign out confirms, clears the active session and shift, then shows welcome',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final auth = FakeAuthRepository(signedIn: true);
      final connector = FakeVoiceConnector();
      final recorder = FakeRecorder();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          onboardingCompletedAtLaunchProvider.overrideWithValue(true),
          ...offlineOverrides(
            connector: connector,
            recorder: recorder,
            api: api,
            companyConnectionStore: connections,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const KoraApp()),
      );
      await settle(tester);

      await container.read(voiceSessionProvider.notifier).startConversation();
      await tester.pump();
      expect(container.read(shiftProvider), 'shift-1');
      expect(
        container.read(voiceSessionProvider).connection,
        VoiceConnection.connected,
      );
      expect(connector.last.closedByClient, isFalse);

      await tester.tap(find.byKey(const Key('profile-button')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('profile-sign-out')));
      await tester.tap(find.byKey(const Key('profile-sign-out')));
      await tester.pump();
      expect(find.text('Sign out?'), findsOneWidget);

      // Dismissing the destructive confirmation leaves everything intact.
      await tester.tap(find.byKey(const Key('profile-sign-out-cancel')));
      await tester.pump();
      expect(auth.signOutCalls, 0);
      expect(container.read(shiftProvider), 'shift-1');
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('profile-sign-out')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('profile-sign-out-confirm')));
      await settle(tester);

      expect(auth.signOutCalls, 1);
      expect(auth.hasValidSession, isFalse);
      expect(connector.last.closedByClient, isTrue);
      expect(
        container.read(voiceSessionProvider).connection,
        VoiceConnection.disconnected,
      );
      expect(container.read(shiftProvider), isNull);
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.byType(WelcomeScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('shows loading, then details with a read-only phone', (
    tester,
  ) async {
    await pumpProfile(tester);
    expect(find.byKey(const Key('profile-loading')), findsOneWidget);
    await tester.pump();

    expect(find.byKey(const Key('profile-loading')), findsNothing);
    expect(field('profile-name'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(field('profile-name')).controller!.text,
      'Ada Obi',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('profile-since'))).data,
      'Driving with Kora since September 2026',
    );

    // The phone is shown, but no text field holds it.
    expect(find.text(_phone), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('profile-phone')),
        matching: find.byType(EditableText),
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == _phone,
      ),
      findsNothing,
    );

    // The vehicle is Settings' control; here it only links there.
    expect(find.byKey(const Key('profile-vehicle-settings')), findsOneWidget);
    await tester.pump();
    expect(find.text('Not linked to a company yet'), findsOneWidget);
  });

  testWidgets('lays out on a small phone without overflow', (tester) async {
    connections.saved['driver-1'] = const PlatformConnection(
      platform: 'a_logistics_platform_with_a_long_name',
    );
    await pumpProfile(tester);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('profile-connect')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    api.profileFailure = const ApiException("Can't reach Kora right now.");
    await pumpProfile(tester);
    await tester.pump();
    expect(find.byKey(const Key('profile-error')), findsOneWidget);
    expect(find.text("Can't reach Kora right now."), findsOneWidget);

    api.profileFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('profile-error')), findsNothing);
    expect(field('profile-name'), findsOneWidget);
  });

  testWidgets('retry also re-runs a failed ensure-profile request', (
    tester,
  ) async {
    api.ensureProfileFailure = const ApiException(
      "Couldn't set up your driver profile.",
    );
    await pumpProfile(tester);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('profile-error')), findsOneWidget);
    expect(find.text("Couldn't set up your driver profile."), findsOneWidget);
    expect(api.ensureProfileCalls, 1);
    expect(api.profileCalls, 0);

    api.ensureProfileFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(api.ensureProfileCalls, 2);
    expect(api.profileCalls, 1);
    expect(find.byKey(const Key('profile-error')), findsNothing);
    expect(field('profile-name'), findsOneWidget);
  });

  testWidgets('saving a new name sends it to the profile endpoint', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.pump();

    // Unchanged: nothing to save.
    await tapKey(tester, 'profile-save');
    expect(api.nameUpdates, isEmpty);

    await enter(tester, 'profile-name', '  Ada Obi-Okafor ');
    await tapKey(tester, 'profile-save');
    expect(api.nameUpdates, ['Ada Obi-Okafor']);
    expect(find.text('Name saved.'), findsOneWidget);

    // The profile reloads everywhere with the saved name.
    expect(api.profileCalls, 2);
    expect(find.text('Ada Obi-Okafor'), findsWidgets);
  });

  testWidgets('a blank name is refused and a failed save says why', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.pump();

    await enter(tester, 'profile-name', '   ');
    await tapKey(tester, 'profile-save');
    expect(api.nameUpdates, isEmpty);
    expect(
      find.text('Enter the name your customers will hear.'),
      findsOneWidget,
    );

    api.updateFailure = const ApiException('Kora had a problem. Try again.');
    await enter(tester, 'profile-name', 'Ada O.');
    await tapKey(tester, 'profile-save');
    expect(api.nameUpdates, ['Ada O.']);
    expect(
      find.descendant(
        of: find.byKey(const Key('profile-save-result')),
        matching: find.text('Kora had a problem. Try again.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a connect code links the company, or says it failed', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.pump();

    // Not six digits: checked before any call.
    await enter(tester, 'profile-connect-code', '12ab');
    await tapKey(tester, 'profile-connect');
    expect(api.connectCodes, isEmpty);
    expect(
      find.text('Enter the 6 digits from your dispatcher.'),
      findsOneWidget,
    );

    api.connectFailure = const ApiException(
      "That code didn't work. Check it with your dispatcher and try again.",
      statusCode: 400,
    );
    await enter(tester, 'profile-connect-code', '000000');
    await tapKey(tester, 'profile-connect');
    expect(api.connectCodes, ['000000']);
    expect(
      find.descendant(
        of: find.byKey(const Key('profile-connect-result')),
        matching: find.textContaining("That code didn't work"),
      ),
      findsOneWidget,
    );
    expect(connections.saved, isEmpty);
    expect(find.text('Not linked to a company yet'), findsOneWidget);

    api.connectFailure = null;
    await enter(tester, 'profile-connect-code', '482913');
    await tapKey(tester, 'profile-connect');
    expect(api.connectCodes, ['000000', '482913']);
    expect(find.text('Connected to Onfleet.'), findsOneWidget);
    expect(find.text('Connected to Onfleet'), findsOneWidget);
    expect(connections.saved['driver-1']?.platform, 'onfleet');
  });

  testWidgets('a remembered company link shows on open', (tester) async {
    connections.saved['driver-1'] = PlatformConnection(
      platform: 'onfleet',
      connectedAt: DateTime(2026, 9, 10, 12),
    );
    await pumpProfile(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('Connected to Onfleet'), findsOneWidget);
    expect(find.text('Linked 10 September 2026'), findsOneWidget);
  });

  group('HttpKoraApi', () {
    HttpKoraApi apiWith(MockClientHandler handler) => HttpKoraApi(
      baseUri: Uri.parse('https://api.voiceops.test'),
      auth: FakeAuthRepository(signedIn: true),
      client: MockClient(handler),
    );

    test('updateDriverName PUTs the name with the bearer token', () async {
      late http.Request sent;
      final api = apiWith((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'id': 'driver-1',
            'name': 'Ada O.',
            'phone': _phone,
            'vehicle_type': 'Motorbike',
            'created_at': '2026-09-03T12:00:00+00:00',
          }),
          200,
        );
      });
      final profile = await api.updateDriverName('Ada O.');
      expect(sent.method, 'PUT');
      expect(
        sent.url.toString(),
        'https://api.voiceops.test/v1/driver/profile',
      );
      expect(sent.headers['Authorization'], 'Bearer test-access-token');
      expect(jsonDecode(sent.body), {'name': 'Ada O.'});
      expect(profile.name, 'Ada O.');
      expect(profile.phone, _phone);
      expect(profile.createdAt, DateTime.utc(2026, 9, 3, 12));
    });

    test('updateDriverVehicle PUTs the vehicle_type', () async {
      late http.Request sent;
      final api = apiWith((request) async {
        sent = request;
        return http.Response(
          jsonEncode({'id': 'driver-1', 'vehicle_type': 'walking'}),
          200,
        );
      });
      final profile = await api.updateDriverVehicle('walking');
      expect(sent.method, 'PUT');
      expect(
        sent.url.toString(),
        'https://api.voiceops.test/v1/driver/profile',
      );
      expect(jsonDecode(sent.body), {'vehicle_type': 'walking'});
      expect(profile.vehicleType, 'walking');
    });

    test('connectWithCode posts the code and reads the platform', () async {
      late http.Request sent;
      final api = apiWith((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'message': 'Platform connected successfully',
            'connection': {
              'platform': 'onfleet',
              'connected_at': '2026-09-17T08:00:00+00:00',
            },
          }),
          200,
        );
      });
      final connection = await api.connectWithCode('482913');
      expect(sent.method, 'POST');
      expect(sent.url.path, '/v1/driver/connect');
      expect(jsonDecode(sent.body), containsPair('connect_code', '482913'));
      expect(connection.platform, 'onfleet');
      expect(connection.connectedAt, DateTime.utc(2026, 9, 17, 8));
    });

    test('an unknown connect code reads as a driver-facing message', () {
      final api = apiWith(
        (_) async => http.Response(
          jsonEncode({'detail': 'Invalid or inactive connect code'}),
          400,
        ),
      );
      expect(
        api.connectWithCode('000000'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having(
                (e) => e.message,
                'message',
                contains("That code didn't work"),
              ),
        ),
      );
    });
  });
}
