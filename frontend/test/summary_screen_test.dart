import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/summary/data/shift_report.dart';
import 'package:voiceops/features/summary/screens/summary_screen.dart';
import 'package:voiceops/features/summary/widgets/shift_report_view.dart';
import 'package:voiceops/providers/shift_provider.dart';
import 'package:voiceops/providers/summary_stream_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'test_fonts.dart';

/// A stored `intelligence_reports` row, as the backend returns it today:
/// DECIMAL columns as strings, incidents nested under `failure_patterns`.
const _reportRow = <String, dynamic>{
  'id': 'report-1',
  'shift_id': 'shift-1',
  'total_deliveries': 20,
  'delivered_count': 17,
  'failed_count': 2,
  'success_rate': '85.00',
  'sentiment_score': '0.82',
  'recommendations': 'Pre-verify gate codes by SMS in congested zones.',
  'route_issues': ['Congestion noted around Marina'],
  'failure_patterns': {
    'executive_summary': 'Driver completed 17 of 20 stops.',
    'incidents': ['Customer security gate access delay', ''],
    'voice_sessions_analyzed': 14,
  },
  'generated_at': '2026-09-16T18:04:00Z',
};

void main() {
  setUpAll(disableGoogleFontsFetching);

  group('ShiftReport.fromJson', () {
    test('reads the stored row, nested incidents and string decimals', () {
      final report = ShiftReport.fromJson(_reportRow);
      expect(report.totalDeliveries, 20);
      expect(report.deliveredCount, 17);
      expect(report.failedCount, 2);
      expect(report.remainingCount, 1);
      expect(report.successRate, 85);
      expect(report.sentimentScore, closeTo(0.82, 1e-9));
      expect(report.incidents, ['Customer security gate access delay']);
      expect(report.routeIssues, ['Congestion noted around Marina']);
      expect(report.executiveSummary, 'Driver completed 17 of 20 stops.');
      expect(report.voiceSessions, 14);
      expect(report.shiftDuration, isNull);
    });

    test('reads the proposed shift timing and top-level incidents', () {
      final report = ShiftReport.fromJson({
        'total_deliveries': 4,
        'delivered_count': 1,
        'failed_count': 0,
        'incidents': ['Road closed'],
        'shift_started_at': '2026-09-16T08:00:00Z',
        'shift_ended_at': '2026-09-16T14:40:00Z',
      });
      expect(report.successRate, 25);
      expect(report.sentimentScore, isNull);
      expect(report.incidents, ['Road closed']);
      expect(report.shiftDuration, const Duration(hours: 6, minutes: 40));
      expect(formatShiftDuration(report.shiftDuration!), '6h 40m');
      expect(formatShiftDuration(const Duration(minutes: 45)), '45m');
    });
  });

  group('HttpVoiceOpsApi.fetchShiftReport', () {
    Future<ShiftReport?> fetch(Map<String, dynamic> body) {
      late http.Request seen;
      final api = HttpVoiceOpsApi(
        baseUri: Uri.parse('https://api.voiceops.test'),
        auth: FakeAuthRepository(signedIn: true),
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode(body), 200);
        }),
      );
      return api.fetchShiftReport('shift-1').whenComplete(() {
        expect(seen.method, 'GET');
        expect(seen.url.path, '/v1/shift/shift-1/report');
        expect(seen.headers['Authorization'], 'Bearer test-access-token');
      });
    }

    test('parses a stored report', () async {
      expect((await fetch(_reportRow))!.deliveredCount, 17);
    });

    test('returns null while the report is processing', () async {
      expect(
        await fetch({
          'status': 'processing',
          'message': 'Report is being generated',
        }),
        isNull,
      );
    });
  });

  group('SummaryScreen', () {
    late FakeVoiceOpsApi api;
    late ProviderContainer container;

    setUp(() => api = FakeVoiceOpsApi());

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      container = ProviderContainer(overrides: offlineOverrides(api: api));
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildVoiceOpsTheme(),
            home: const Scaffold(body: SummaryScreen()),
          ),
        ),
      );
    }

    // The loading spinner animates forever, so step time explicitly.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(KoraMotion.slow * 2);
    }

    Future<void> finishSummary(WidgetTester tester, String text) async {
      await container.read(shiftProvider.notifier).ensureStarted();
      container
          .read(summaryStreamProvider.notifier)
          .append(text, isFinal: true);
      await settle(tester);
    }

    testWidgets('no summary yet keeps the prompt and fetches nothing', (
      tester,
    ) async {
      await pump(tester);
      await settle(tester);

      expect(find.text('Your shift summary'), findsOneWidget);
      expect(find.textContaining('how did my shift go?'), findsOneWidget);
      expect(find.byType(ShiftReportView), findsNothing);
      expect(api.reportRequests, isEmpty);
    });

    testWidgets('a streaming summary shows the live text, no report yet', (
      tester,
    ) async {
      api.report = ShiftReport.fromJson(_reportRow);
      await pump(tester);
      await container.read(shiftProvider.notifier).ensureStarted();
      container
          .read(summaryStreamProvider.notifier)
          .append('Today you did ', isFinal: false);
      await settle(tester);

      expect(find.text('SHIFT SUMMARY - LIVE'), findsOneWidget);
      expect(find.text('Today you did '), findsOneWidget);
      expect(find.byType(ShiftReportView), findsNothing);
      expect(api.reportRequests, isEmpty);

      container
          .read(summaryStreamProvider.notifier)
          .append('17 stops.', isFinal: false);
      await settle(tester);
      expect(find.text('Today you did 17 stops.'), findsOneWidget);
    });

    testWidgets('a finished summary renders the structured report', (
      tester,
    ) async {
      api.report = ShiftReport.fromJson(_reportRow);
      await pump(tester);
      await finishSummary(tester, 'Today you did 17 stops.');

      expect(api.reportRequests, ['shift-1']);
      expect(find.byType(ShiftReportView), findsOneWidget);
      expect(find.text('SHIFT SUMMARY - LIVE'), findsNothing);

      // Success ring and headline count.
      expect(find.text('85%'), findsOneWidget);
      expect(find.text('17 of 20 delivered'), findsOneWidget);
      expect(find.bySemanticsLabel('85 percent success rate'), findsOneWidget);

      // Stat grid: no shift timing yet, so voice check-ins fill the fourth.
      expect(find.bySemanticsLabel('Delivered: 17'), findsOneWidget);
      expect(find.bySemanticsLabel('Failed: 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Remaining: 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Voice check-ins: 14'), findsOneWidget);
      expect(find.byKey(const Key('stat-On shift')), findsNothing);

      // The streamed recap wins over the report's own summary.
      expect(find.text('Today you did 17 stops.'), findsOneWidget);
      expect(find.text('Driver completed 17 of 20 stops.'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('report-coach-note')),
        200,
      );
      expect(find.text('Calm and steady'), findsOneWidget);
      expect(find.text('INCIDENTS - 1'), findsOneWidget);
      expect(find.text('Customer security gate access delay'), findsOneWidget);
      expect(find.text('Congestion noted around Marina'), findsOneWidget);
      expect(find.text("COACH'S NOTE"), findsOneWidget);
      expect(
        find.text('Pre-verify gate codes by SMS in congested zones.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty report hides incidents, sentiment and the note', (
      tester,
    ) async {
      api.report = ShiftReport.fromJson({
        'total_deliveries': 0,
        'delivered_count': 0,
        'failed_count': 0,
        'success_rate': 0,
        'shift_started_at': '2026-09-16T08:00:00Z',
        'shift_ended_at': '2026-09-16T08:45:00Z',
      });
      await pump(tester);
      await finishSummary(tester, 'A quiet shift.');

      expect(find.text('No stops on this shift'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.bySemanticsLabel('On shift: 45m'), findsOneWidget);
      expect(find.byKey(const Key('report-sentiment')), findsNothing);
      expect(find.byKey(const Key('report-incidents')), findsNothing);
      expect(find.byKey(const Key('report-route-issues')), findsNothing);
      expect(find.byKey(const Key('report-coach-note')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a report still processing offers to check again', (
      tester,
    ) async {
      await pump(tester);
      await finishSummary(tester, 'Today you did 17 stops.');

      expect(find.byKey(const Key('report-processing')), findsOneWidget);
      expect(find.text('Today you did 17 stops.'), findsOneWidget);
      expect(find.byType(ShiftReportView), findsNothing);

      api.report = ShiftReport.fromJson(_reportRow);
      await tester.tap(find.text('Check again'));
      await settle(tester);

      expect(api.reportRequests, ['shift-1', 'shift-1']);
      expect(find.byType(ShiftReportView), findsOneWidget);
    });

    testWidgets('a failed fetch shows the error with a retry', (tester) async {
      api.reportFailure = const ApiException('VoiceOps had a problem.');
      await pump(tester);
      await finishSummary(tester, 'Today you did 17 stops.');

      expect(find.byKey(const Key('report-error')), findsOneWidget);
      expect(find.text('VoiceOps had a problem.'), findsOneWidget);

      api
        ..reportFailure = null
        ..report = ShiftReport.fromJson(_reportRow);
      await tester.tap(find.text('Check again'));
      await settle(tester);

      expect(find.byKey(const Key('report-error')), findsNothing);
      expect(find.byType(ShiftReportView), findsOneWidget);
    });
  });
}
