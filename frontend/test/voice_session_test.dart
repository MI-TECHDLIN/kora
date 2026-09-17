import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/app/router.dart';
import 'package:voiceops/core/api/voiceops_api.dart' show ApiException;
import 'package:voiceops/core/audio/voice_recorder.dart';
import 'package:voiceops/core/config/backend_config.dart';
import 'package:voiceops/core/realtime/voice_events.dart';
import 'package:voiceops/mascot/mascot_state.dart';
import 'package:voiceops/providers/agent_state_provider.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/call_provider.dart';
import 'package:voiceops/providers/co_rider_voice_provider.dart';
import 'package:voiceops/providers/map_route_provider.dart';
import 'package:voiceops/providers/navigation_provider.dart';
import 'package:voiceops/providers/notification_preferences_provider.dart';
import 'package:voiceops/providers/push_to_talk_provider.dart';
import 'package:voiceops/providers/summary_stream_provider.dart';
import 'package:voiceops/providers/task_progress_provider.dart';
import 'package:voiceops/providers/transcript_provider.dart';
import 'package:voiceops/providers/voice_session_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'map_route_test.dart' show sampleMapRoute;

/// Records agent navigation instead of driving a real router.
class _FakeNavigation implements NavigationActions {
  final screens = <String>[];

  @override
  void navigateForAgent(String screenKey) => screens.add(screenKey);

  @override
  void goTo(MainTab tab) => screens.add(tab.name);
}

void main() {
  late FakeVoiceConnector connector;
  late FakeRecorder recorder;
  late FakePlayback playback;
  late FakeVoiceOpsApi api;
  late FakeAuthRepository auth;
  late _FakeNavigation navigation;
  late FakeCoRiderVoiceStore voices;
  late ProviderContainer container;

  setUp(() {
    connector = FakeVoiceConnector();
    recorder = FakeRecorder();
    playback = FakePlayback();
    api = FakeVoiceOpsApi();
    auth = FakeAuthRepository(signedIn: true);
    navigation = _FakeNavigation();
    voices = FakeCoRiderVoiceStore();
  });

  /// Runs [body] on fake time, so the reconnect and answer timers are
  /// stepped explicitly. `flush` delivers everything pending: socket
  /// frames, mic chunks, the session's own async steps.
  void onFakeTime(
    void Function(FakeAsync async, void Function() flush) body, {
    bool configured = true,
  }) {
    fakeAsync((async) {
      container = ProviderContainer(
        overrides: [
          ...offlineOverrides(
            connector: connector,
            recorder: recorder,
            playback: playback,
            api: api,
            coRiderVoiceStore: voices,
            backendConfigured: configured,
          ),
          authRepositoryProvider.overrideWithValue(auth),
          navigationProvider.overrideWithValue(navigation),
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
  PushToTalkState ptt() => container.read(pushToTalkProvider);
  VoiceSessionState voice() => container.read(voiceSessionProvider);

  test('a turn: connect, stream the mic, send, hear the reply', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      expect(ptt(), PushToTalkState.recording);
      expect(api.shiftCalls, 1);
      final socket = connector.last;
      // No saved voice: Anna, the backend's default.
      expect(
        socket.uri.toString(),
        'wss://api.voiceops.test/ws/voice/shift-1?voice=anna',
      );
      expect(socket.headers, {'Authorization': 'Bearer test-access-token'});
      expect(voice().connection, VoiceConnection.connected);

      // 5000 bytes of speech -> two 50 ms frames now, the rest on release.
      recorder.speak(Uint8List(5000));
      flush();
      expect(socket.sentAudio.map((f) => f.length), [2400, 2400]);

      session().onPushToTalk();
      flush();
      expect(ptt(), PushToTalkState.idle);
      expect(recorder.isRecording, isFalse);
      expect(socket.sentAudio[2].length, 200);
      // Trailing silence so the backend's turn detection hears the end.
      final silence = socket.sentAudio.skip(3).toList();
      expect(silence, hasLength(16));
      expect(silence.every((f) => f.length == voiceFrameBytes), isTrue);
      expect(silence.every((f) => f.every((b) => b == 0)), isTrue);

      socket.emitAudio(Uint8List(960));
      flush();
      expect(ptt(), PushToTalkState.speaking);
      expect(playback.played, hasLength(1));

      socket.emit({'event': 'reply_done'});
      flush();
      expect(ptt(), PushToTalkState.idle);
      expect(playback.flushes, 1);

      // The next turn reuses the open socket and shift.
      session().onPushToTalk();
      flush();
      expect(ptt(), PushToTalkState.recording);
      expect(connector.sockets, hasLength(1));
      expect(api.shiftCalls, 1);
    });
  });

  test('the saved co-rider voice rides on the voice socket', () {
    voices.value = CoRiderVoice.michael;
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      expect(connector.last.uri.queryParameters, {'voice': 'michael'});
    });
  });

  test('every server event reaches the provider that renders it', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      final socket = connector.last;

      socket
        ..emit({'event': 'agent_state', 'state': 'mapping'})
        ..emit({'event': 'screen_navigate', 'screen': 'map'})
        ..emit({
          'event': 'task_step',
          'step': 'Checking delivery route',
          'status': 'active',
        })
        ..emit(sampleMapRoute())
        ..emit({
          'event': 'transcript',
          'role': 'driver',
          'text': "What's my next stop?",
        })
        ..emit({
          'event': 'transcript',
          'role': 'agent',
          'text': 'Amara on Broad Street.',
        })
        ..emit({'event': 'summary_chunk', 'text': 'Today you ', 'final': false})
        ..emit({
          'event': 'summary_chunk',
          'text': 'did 7 stops.',
          'final': true,
        })
        ..emit({
          'event': 'call_started',
          'call_id': 'c-1',
          'delivery_id': 'd-4',
          'customer_name': 'Amara J.',
          'sequence': 4,
        })
        // Unknown and malformed frames are skipped, never fatal.
        ..emit({'event': 'from_the_future'})
        ..emit({'event': 'agent_state'});
      flush();

      expect(container.read(agentStateProvider), AgentState.mapping);
      expect(navigation.screens, ['map']);
      expect(
        container.read(taskProgressProvider).single.status,
        TaskStepStatus.active,
      );
      expect(
        container.read(mapRouteProvider)!.target!.recipientName,
        'Amara Johnson',
      );
      expect(container.read(transcriptProvider).map((l) => (l.role, l.text)), [
        (SpeakerRole.driver, "What's my next stop?"),
        (SpeakerRole.agent, 'Amara on Broad Street.'),
      ]);
      final summary = container.read(summaryStreamProvider)!;
      expect(summary.text, 'Today you did 7 stops.');
      expect(summary.isComplete, isTrue);
      expect(container.read(activeCallProvider)!.customerName, 'Amara J.');

      // The call overlay's end button sends end_call; call_ended closes it.
      expect(session().endCall('c-1'), isTrue);
      expect(socket.sentText.last, {'event': 'end_call', 'call_id': 'c-1'});
      socket.emit({'event': 'call_ended', 'call_id': 'c-1'});
      flush();
      expect(container.read(activeCallProvider), isNull);

      socket.emit({
        'event': 'error',
        'code': 'upstream_timeout',
        'message': 'Your co-rider is slow to answer.',
      });
      flush();
      expect(voice().issue, 'Your co-rider is slow to answer.');
      expect(voice().connection, VoiceConnection.connected);
    });
  });

  test('a completed shift summary opens by default', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();

      connector.last
        ..emit({'event': 'screen_navigate', 'screen': 'summary'})
        ..emit({
          'event': 'summary_chunk',
          'text': 'You completed 12 stops.',
          'final': true,
        })
        ..emit({'event': 'reply_done'});
      flush();

      expect(navigation.screens, ['summary']);
      expect(container.read(summaryStreamProvider)?.isComplete, isTrue);
    });
  });

  test(
    'a disabled shift-summary notification keeps the report without opening it',
    () {
      onFakeTime((async, flush) {
        container
            .read(notificationPreferencesProvider.notifier)
            .setShiftSummaryReady(enabled: false);
        flush();
        session().onPushToTalk();
        flush();

        connector.last
          ..emit({'event': 'screen_navigate', 'screen': 'summary'})
          ..emit({
            'event': 'summary_chunk',
            'text': 'You completed 12 stops.',
            'final': true,
          })
          ..emit({'event': 'reply_done'});
        flush();

        expect(navigation.screens, isEmpty);
        final summary = container.read(summaryStreamProvider)!;
        expect(summary.text, 'You completed 12 stops.');
        expect(summary.isComplete, isTrue);
      });
    },
  );

  test('a route frames the map; a bare map screen follows the driver', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      final socket = connector.last;
      MapFocus focus() => container.read(mapFocusProvider);

      // Route tools: screen_navigate then map_route, back to back.
      socket
        ..emit({'event': 'screen_navigate', 'screen': 'map'})
        ..emit(sampleMapRoute())
        ..emit({
          'event': 'task_step',
          'step': 'Checking delivery route',
          'status': 'done',
        });
      flush();
      async.elapse(const Duration(seconds: 1));
      expect(focus().target, MapFocusTarget.route);

      // "Where am I?": show_screen sends screen_navigate: map alone. The
      // next event settles it...
      socket
        ..emit({'event': 'screen_navigate', 'screen': 'map'})
        ..emit({'event': 'task_step', 'step': 'Opening map', 'status': 'done'});
      flush();
      expect(focus().target, MapFocusTarget.driver);
      final serial = focus().serial;

      // ...and so does a quiet socket, a moment later. Asking again
      // re-centres even though the target is unchanged.
      socket.emit({'event': 'screen_navigate', 'screen': 'map'});
      flush();
      expect(focus().serial, serial);
      async.elapse(const Duration(milliseconds: 400));
      expect(focus().target, MapFocusTarget.driver);
      expect(focus().serial, greaterThan(serial));
      // The route stays drawn; only the camera moves.
      expect(container.read(mapRouteProvider), isNotNull);

      // Other screens never touch the map camera.
      final before = focus().serial;
      socket
        ..emit({'event': 'screen_navigate', 'screen': 'settings'})
        ..emit({'event': 'agent_state', 'state': 'idle'});
      flush();
      async.elapse(const Duration(seconds: 1));
      expect(focus().serial, before);
      expect(navigation.screens.last, 'settings');
    });
  });

  test('every agent_state key reaches the co-rider as its own mood', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      final socket = connector.last;

      for (final mood in AgentState.values.reversed) {
        socket.emit({'event': 'agent_state', 'state': mood.riveKey});
        flush();
        expect(container.read(agentStateProvider), mood);
      }
    });
  });

  test('the co-rider shows speaking while its reply plays', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      final socket = connector.last;

      socket.emit({'event': 'agent_state', 'state': 'thinking'});
      flush();
      socket
        ..emitAudio(Uint8List(960))
        ..emit({'event': 'agent_state', 'state': 'speaking'});
      flush();
      expect(container.read(agentStateProvider), AgentState.speaking);
      // The button keeps its own speaking state; the orb's mood is separate.
      expect(ptt(), PushToTalkState.speaking);

      socket
        ..emit({'event': 'reply_done'})
        ..emit({'event': 'agent_state', 'state': 'idle'});
      flush();
      expect(container.read(agentStateProvider), AgentState.idle);
      expect(ptt(), PushToTalkState.idle);
    });
  });

  test('a tool turn: no reply_done until the answer after the tools', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      final socket = connector.last;

      // "Let me check…" plays while the tools run; no reply_done follows it.
      socket.emitAudio(Uint8List(960));
      flush();
      expect(ptt(), PushToTalkState.speaking);
      socket
        ..emit({'event': 'agent_state', 'state': 'mapping'})
        ..emit({
          'event': 'task_step',
          'step': 'Checking delivery route',
          'status': 'active',
        });
      flush();
      async.elapse(const Duration(seconds: 5));
      expect(ptt(), PushToTalkState.speaking);

      // The answer with the results, which does end with reply_done.
      socket
        ..emit({
          'event': 'task_step',
          'step': 'Checking delivery route',
          'status': 'done',
        })
        ..emitAudio(Uint8List(960))
        ..emit({'event': 'reply_done'});
      flush();
      expect(ptt(), PushToTalkState.idle);
      expect(playback.played, hasLength(2));
      expect(voice().issue, isNull);
    });
  });

  test('frees push-to-talk when a reply never closes its turn', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      connector.last.emitAudio(Uint8List(960));
      flush();
      expect(ptt(), PushToTalkState.speaking);
      async.elapse(const Duration(seconds: 21));
      expect(ptt(), PushToTalkState.idle);
      // It did answer, so there is nothing to warn the driver about.
      expect(voice().issue, isNull);
    });
  });

  test('a drop while the co-rider speaks frees push-to-talk', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      connector.last.emitAudio(Uint8List(960));
      flush();
      expect(ptt(), PushToTalkState.speaking);
      connector.last.drop();
      flush();
      expect(ptt(), PushToTalkState.idle);
      expect(voice().connection, VoiceConnection.reconnecting);
    });
  });

  test('the next driver turn unmutes a reply that never closed', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      final socket = connector.last;
      socket.emitAudio(Uint8List(960)); // a tool turn's first reply
      flush();
      session().onPushToTalk(); // barge in
      flush();
      session().onPushToTalk(); // send
      flush();

      // No reply_done for the reply talked over; the new turn's transcript
      // arrives, then its answer must be heard.
      socket
        ..emit({'event': 'transcript', 'role': 'driver', 'text': 'Stop.'})
        ..emitAudio(Uint8List(960));
      flush();
      expect(playback.played, hasLength(2));
      expect(ptt(), PushToTalkState.speaking);
    });
  });

  test('talking over the co-rider cuts it off until reply_done', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      final socket = connector.last;
      socket.emitAudio(Uint8List(960));
      flush();
      expect(ptt(), PushToTalkState.speaking);

      session().onPushToTalk(); // barge in
      flush();
      expect(playback.stops, 1);
      expect(ptt(), PushToTalkState.recording);
      socket.emitAudio(Uint8List(960)); // the rest of the old reply
      flush();
      expect(playback.played, hasLength(1));
      expect(ptt(), PushToTalkState.recording);

      socket.emit({'event': 'reply_done'});
      flush();
      expect(ptt(), PushToTalkState.recording);
      session().onPushToTalk();
      flush();
      socket.emitAudio(Uint8List(960)); // the new reply plays
      flush();
      expect(playback.played, hasLength(2));
      expect(ptt(), PushToTalkState.speaking);
    });
  });

  test('a dropped socket reconnects with backoff and says so', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      connector.serverUp = false;
      connector.last.drop();
      flush();

      expect(voice().connection, VoiceConnection.reconnecting);
      expect(voice().issue, contains('Reconnecting'));
      expect(ptt(), PushToTalkState.idle);

      // 1 s: the first retry fails; 2 s later the next one gets through.
      async.elapse(const Duration(seconds: 1));
      expect(connector.sockets, hasLength(2));
      expect(voice().connection, VoiceConnection.reconnecting);
      connector.serverUp = true;
      async.elapse(const Duration(seconds: 2));
      expect(connector.sockets, hasLength(3));
      expect(voice().connection, VoiceConnection.connected);
      expect(voice().issue, isNull);
      // Same shift: reconnecting doesn't start a new one.
      expect(api.shiftCalls, 1);
    });
  });

  test('gives up after the backoff runs out, until the next press', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      connector.serverUp = false;
      connector.last.drop();
      flush();
      for (final seconds in [1, 2, 4, 8, 16]) {
        async.elapse(Duration(seconds: seconds));
      }
      expect(voice().connection, VoiceConnection.failed);
      expect(voice().issue, contains('Tap the mic'));
      async.elapse(const Duration(minutes: 1));
      expect(connector.sockets, hasLength(6)); // no more retries

      connector.serverUp = true;
      session().onPushToTalk();
      flush();
      expect(ptt(), PushToTalkState.recording);
      expect(voice().connection, VoiceConnection.connected);
    });
  });

  test('a rejected token stops reconnecting', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      final socket = connector.last;
      socket.emit({
        'event': 'error',
        'code': 'auth_failed',
        'message': 'Sign in again.',
      });
      socket.drop();
      flush();
      async.elapse(const Duration(seconds: 30));
      expect(voice().connection, VoiceConnection.failed);
      expect(voice().issue, 'Sign in again.');
      expect(connector.sockets, hasLength(1));
    });
  });

  test('frees push-to-talk when the co-rider never answers', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      connector.last.emit({
        'event': 'transcript',
        'role': 'driver',
        'text': 'What is my next stop?',
      });
      flush();
      expect(ptt(), PushToTalkState.processing);
      async.elapse(const Duration(seconds: 21));
      expect(ptt(), PushToTalkState.recording);
      expect(voice().issue, contains("didn't answer"));
    });
  });

  test('says what blocks voice instead of failing silently', () {
    onFakeTime((async, flush) {
      recorder.permitted = false;
      session().onPushToTalk();
      flush();
      expect(ptt(), PushToTalkState.idle);
      expect(voice().issue, contains('microphone'));
      expect(connector.sockets, isEmpty);

      recorder.permitted = true;
      api.shiftFailure = const ApiException('VoiceOps had a problem.');
      session().onPushToTalk();
      flush();
      expect(ptt(), PushToTalkState.idle);
      expect(voice().connection, VoiceConnection.failed);
      expect(voice().issue, 'VoiceOps had a problem.');
      expect(connector.sockets, isEmpty);
    });
  });

  test('a missing backend URI says what blocks voice', () {
    onFakeTime(configured: false, (async, flush) {
      session().onPushToTalk();
      flush();
      expect(ptt(), PushToTalkState.idle);
      expect(voice().issue, BackendConfig.notConfiguredMessage);
      expect(connector.sockets, isEmpty);
    });
  });

  test('signing out closes the session', () {
    onFakeTime((async, flush) {
      session().onPushToTalk();
      flush();
      session().onPushToTalk();
      flush();
      final socket = connector.last;
      auth.signOut();
      flush();
      expect(socket.closedByClient, isTrue);
      expect(voice().connection, VoiceConnection.disconnected);
      async.elapse(const Duration(seconds: 30));
      expect(connector.sockets, hasLength(1));
    });
  });
}
