import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/config/backend_config.dart';
import 'package:voiceops/core/realtime/voice_events.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/settings/screens/settings_screen.dart';

import 'fake_voice.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  group('backendLabel', () {
    test('is the host, plus a non-default port', () {
      expect(
        backendLabel(Uri.parse('https://kora-brd8.onrender.com')),
        'kora-brd8.onrender.com',
      );
      expect(
        backendLabel(Uri.parse('https://kora-brd8.onrender.com:443/x')),
        'kora-brd8.onrender.com',
      );
      expect(
        backendLabel(Uri.parse('http://192.168.1.100:8000')),
        '192.168.1.100:8000',
      );
      expect(backendLabel(null), 'no backend');
    });
  });

  group('isDevelopmentBackend', () {
    test('flags plain http and loopback / LAN hosts', () {
      for (final url in [
        'http://192.168.1.100:8000',
        'https://192.168.18.13',
        'https://10.0.2.2',
        'http://localhost:8000',
        'https://172.20.0.5',
        'http://kora-brd8.onrender.com',
      ]) {
        expect(isDevelopmentBackend(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('accepts the production deployment', () {
      expect(
        isDevelopmentBackend(Uri.parse(BackendConfig.productionUrl)),
        isFalse,
      );
      expect(
        isDevelopmentBackend(Uri.parse('https://api.voiceops.test')),
        isFalse,
      );
      expect(isDevelopmentBackend(null), isFalse);
    });
  });

  group('ErrorEvent', () {
    test('voice_not_configured and auth_failed are fatal', () {
      expect(
        const ErrorEvent(code: 'voice_not_configured', message: '').isFatal,
        isTrue,
      );
      expect(
        const ErrorEvent(code: 'auth_failed', message: '').isFatal,
        isTrue,
      );
      expect(
        const ErrorEvent(code: 'upstream_unavailable', message: '').isFatal,
        isFalse,
      );
      expect(
        const ErrorEvent(code: 'session_expired', message: '').isFatal,
        isFalse,
      );
    });

    test('shows the backend message, or a sentence for the code', () {
      expect(
        const ErrorEvent(
          code: 'internal',
          message: 'Could not load your shift.',
        ).displayMessage,
        'Could not load your shift.',
      );
      for (final code in [
        'auth_failed',
        'session_expired',
        'voice_not_configured',
        'upstream_unavailable',
        'upstream_timeout',
        'internal',
        'something_new',
      ]) {
        expect(ErrorEvent(code: code, message: '').displayMessage, isNotEmpty);
      }
      expect(
        const ErrorEvent(
          code: 'voice_not_configured',
          message: '',
        ).displayMessage,
        contains('set up'),
      );
    });
  });

  testWidgets('Settings names the backend this build talks to', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        koraApiProvider.overrideWithValue(FakeKoraApi()),
        backendUriProvider.overrideWithValue(
          Uri.parse('https://kora-brd8.onrender.com'),
        ),
      ],
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
    await tester.scrollUntilVisible(find.byKey(const Key('backend-host')), 300);

    expect(find.text('kora-brd8.onrender.com'), findsOneWidget);
    expect(find.byKey(const Key('backend-host-warning')), findsNothing);
  });

  testWidgets('Settings warns when the build is not pointed at production', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        koraApiProvider.overrideWithValue(FakeKoraApi()),
        backendUriProvider.overrideWithValue(
          Uri.parse('http://192.168.1.100:8000'),
        ),
      ],
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
    await tester.scrollUntilVisible(find.byKey(const Key('backend-host')), 300);

    expect(find.text('192.168.1.100:8000'), findsOneWidget);
    expect(find.byKey(const Key('backend-host-warning')), findsOneWidget);
  });
}
