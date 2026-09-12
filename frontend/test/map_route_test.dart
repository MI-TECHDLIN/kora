import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:voiceops/core/audio/voice_playback.dart';
import 'package:voiceops/core/config/backend_config.dart';
import 'package:voiceops/core/realtime/voice_events.dart';
import 'package:voiceops/features/map/data/map_route.dart';
import 'package:voiceops/features/map/data/polyline_codec.dart';
import 'package:voiceops/providers/task_progress_provider.dart';

/// Google's reference example for the encoded polyline format.
const _googleExample = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

/// A `map_route` event exactly as docs/contracts/interface.md §1 shows it.
Map<String, Object?> sampleMapRoute() => {
  'event': 'map_route',
  'delivery_id': 'd-4',
  'stops': [
    {
      'delivery_id': 'd-4',
      'sequence': 4,
      'recipient_name': 'Amara Johnson',
      'address': '14 Broad Street, Lagos Island',
      'latitude': 6.4541,
      'longitude': 3.3947,
    },
    {
      'delivery_id': 'd-5',
      'sequence': 5,
      'recipient_name': 'Tunde Bakare',
      'address': '3 Marina Road, Lagos Island',
      'latitude': 6.4489,
      'longitude': 3.4012,
    },
  ],
  'polyline': 'cqkf@{_vSzEcLfJwLjMwL',
  'summary': 'Victoria Bridge',
  'distance_km': 3.2,
  'duration_mins': 11,
  'duration_text': '11 mins',
};

/// `map_route` when Directions found no road route (contract 1.1): the one
/// stop, `polyline: ""`, and null trip stats.
Map<String, Object?> noRoadMapRoute() => {
  ...sampleMapRoute(),
  'stops': [(sampleMapRoute()['stops']! as List).first],
  'polyline': '',
  'summary': null,
  'distance_km': null,
  'duration_mins': null,
  'duration_text': null,
};

void main() {
  group('decodePolyline', () {
    test("decodes Google's reference example", () {
      final points = decodePolyline(_googleExample);
      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 1e-5));
      expect(points[0].longitude, closeTo(-120.2, 1e-5));
      expect(points[1].latitude, closeTo(40.7, 1e-5));
      expect(points[1].longitude, closeTo(-120.95, 1e-5));
      expect(points[2].latitude, closeTo(43.252, 1e-5));
      expect(points[2].longitude, closeTo(-126.453, 1e-5));
    });

    test('rejects a truncated string', () {
      expect(() => decodePolyline('_p~iF~ps|'), throwsFormatException);
    });
  });

  group('MapRoute.fromJson', () {
    test('reads the contract shape', () {
      final route = MapRoute.fromJson(sampleMapRoute());
      expect(route.deliveryId, 'd-4');
      expect(route.stops, hasLength(2));
      expect(route.target!.recipientName, 'Amara Johnson');
      expect(route.target!.sequence, 4);
      expect(route.target!.point, const LatLng(6.4541, 3.3947));
      expect(route.path, hasLength(4));
      expect(route.path.last.latitude, closeTo(6.4489, 1e-5));
      expect(route.line, same(route.path));
      expect(route.etaLabel, '11 mins');
      expect(route.distanceKm, 3.2);
      expect(route.summary, 'Victoria Bridge');
    });

    test('no road route: the stop stays, the line and stats go', () {
      final route = MapRoute.fromJson(noRoadMapRoute());
      expect(route.stops.single.recipientName, 'Amara Johnson');
      expect(route.path, isEmpty);
      expect(route.line, isEmpty);
      expect(route.coordinates, [route.stops.single.point]);
      expect(route.hasTripStats, isFalse);
      expect(route.etaLabel, isNull);
      expect(route.summary, isNull);
    });

    test('draws no line when the polyline is missing or broken', () {
      for (final polyline in [null, '', '_p~iF~ps|']) {
        final route = MapRoute.fromJson({
          ...sampleMapRoute(),
          'polyline': polyline,
        });
        expect(route.path, isEmpty);
        expect(route.line, isEmpty);
        expect(route.hasTripStats, isTrue);
      }
    });

    test('drops stops without coordinates and falls back to the first', () {
      final route = MapRoute.fromJson({
        'delivery_id': 'unknown',
        'stops': [
          {'delivery_id': 'a', 'sequence': 1},
          {'delivery_id': 'b', 'latitude': 1, 'longitude': 2},
        ],
      });
      expect(route.stops.map((s) => s.deliveryId), ['b']);
      expect(route.target!.deliveryId, 'b');
      expect(route.etaLabel, isNull);
    });
  });

  group('VoiceEvent.parse', () {
    test('decodes every contract event', () {
      expect(
        VoiceEvent.parse({'event': 'agent_state', 'state': 'thinking'}),
        isA<AgentStateEvent>().having((e) => e.state, 'state', 'thinking'),
      );
      expect(
        VoiceEvent.parse({'event': 'screen_navigate', 'screen': 'map'}),
        isA<ScreenNavigateEvent>().having((e) => e.screen, 'screen', 'map'),
      );
      expect(
        VoiceEvent.parse({
          'event': 'task_step',
          'step': 'Checking delivery route',
          'status': 'active',
        }),
        isA<TaskStepEvent>().having(
          (e) => e.status,
          'status',
          TaskStepStatus.active,
        ),
      );
      expect(VoiceEvent.parse(sampleMapRoute()), isA<MapRouteEvent>());
      expect(
        VoiceEvent.parse({
          'event': 'call_started',
          'call_id': 'c-1',
          'delivery_id': 'd-4',
          'customer_name': 'Amara J.',
          'sequence': 4,
        }),
        isA<CallStartedEvent>()
            .having((e) => e.customerName, 'name', 'Amara J.')
            .having((e) => e.sequence, 'sequence', 4),
      );
      // The backend doesn't always know the stop number (contract 1.1).
      expect(
        VoiceEvent.parse({
          'event': 'call_started',
          'call_id': 'c-2',
          'delivery_id': 'd-9',
          'customer_name': 'Ada L.',
          'sequence': null,
        }),
        isA<CallStartedEvent>().having((e) => e.sequence, 'sequence', isNull),
      );
      expect(
        VoiceEvent.parse({'event': 'call_ended', 'call_id': 'c-1'}),
        isA<CallEndedEvent>(),
      );
      expect(
        VoiceEvent.parse({
          'event': 'summary_chunk',
          'text': 'Today you completed…',
          'final': true,
        }),
        isA<SummaryChunkEvent>().having((e) => e.isFinal, 'final', true),
      );
      expect(
        VoiceEvent.parse({
          'event': 'transcript',
          'role': 'driver',
          'text': "What's my next stop?",
        }),
        isA<TranscriptEvent>().having((e) => e.role, 'role', SpeakerRole.driver),
      );
      expect(VoiceEvent.parse({'event': 'reply_done'}), isA<ReplyDoneEvent>());
      expect(
        VoiceEvent.parse({
          'event': 'error',
          'code': 'auth_failed',
          'message': 'Sign in again.',
        }),
        isA<ErrorEvent>().having((e) => e.isFatal, 'fatal', true),
      );
    });

    test('skips unknown events and rejects a known one missing fields', () {
      expect(VoiceEvent.parse({'event': 'something_new'}), isNull);
      expect(
        () => VoiceEvent.parse({'event': 'agent_state'}),
        throwsFormatException,
      );
    });
  });

  test('voice socket and REST URLs follow the contract', () {
    final base = Uri.parse('https://api.voiceops.test/');
    expect(
      voiceSocketUri(base, 'shift 1').toString(),
      'wss://api.voiceops.test/ws/voice/shift%201',
    );
    expect(
      voiceSocketUri(Uri.parse('http://10.0.2.2:8000'), 's').toString(),
      'ws://10.0.2.2:8000/ws/voice/s',
    );
    expect(
      restUri(base, 'v1/driver/profile').toString(),
      'https://api.voiceops.test/v1/driver/profile',
    );
  });

  test('pcm16Wav writes a 24 kHz mono PCM16 header', () {
    final wav = pcm16Wav(Uint8List(4800));
    final header = ByteData.sublistView(wav, 0, 44);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(header.getUint16(22, Endian.little), 1); // mono
    expect(header.getUint32(24, Endian.little), 24000);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(40, Endian.little), 4800);
    expect(wav.length, 44 + 4800);
  });

  test('task steps update in place and a new task replaces a finished one', () {
    final tasks = TaskProgressNotifier();
    tasks.applyStep('Checking delivery route', TaskStepStatus.active);
    tasks.applyStep('Texting the customer', TaskStepStatus.pending);
    tasks.applyStep('Checking delivery route', TaskStepStatus.done);
    expect(tasks.state.map((s) => s.status), [
      TaskStepStatus.done,
      TaskStepStatus.pending,
    ]);
    tasks.applyStep('Texting the customer', TaskStepStatus.done);
    tasks.applyStep('Calling Amara', TaskStepStatus.active);
    expect(tasks.state.map((s) => s.label), ['Calling Amara']);
  });
}
