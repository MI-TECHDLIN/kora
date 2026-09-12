import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../core/api/voiceops_api.dart';
import '../core/audio/voice_playback.dart';
import '../core/audio/voice_recorder.dart';
import '../core/config/backend_config.dart';
import '../core/realtime/voice_events.dart';
import '../core/realtime/voice_socket.dart';
import 'agent_state_provider.dart';
import 'auth_provider.dart';
import 'call_provider.dart';
import 'map_route_provider.dart';
import 'navigation_provider.dart';
import 'push_to_talk_provider.dart';
import 'shift_provider.dart';
import 'summary_stream_provider.dart';
import 'task_progress_provider.dart';
import 'transcript_provider.dart';

enum VoiceConnection {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

class VoiceSessionState {
  const VoiceSessionState({
    this.connection = VoiceConnection.disconnected,
    this.issue,
  });

  final VoiceConnection connection;

  /// Why voice is degraded right now, or null. Safe to show the driver.
  final String? issue;
}

/// The voice session: the app's single WebSocket owner (frontend rules).
/// It streams the mic up while push-to-talk is `recording`, plays the
/// co-rider's audio, and hands every server event to the provider that
/// renders it (docs/contracts/interface.md §1).
final voiceSessionProvider =
    StateNotifierProvider<VoiceSession, VoiceSessionState>(VoiceSession.new);

class VoiceSession extends StateNotifier<VoiceSessionState> {
  VoiceSession(this._ref) : super(const VoiceSessionState()) {
    _authSubscription = _ref.read(authRepositoryProvider).changes.listen((
      event,
    ) {
      if (event == AuthChangeEvent.signedOut) {
        disconnect();
        _ref.read(shiftProvider.notifier).clear();
      }
    });
  }

  final Ref _ref;
  late final StreamSubscription<AuthChangeEvent> _authSubscription;

  VoiceSocket? _socket;
  StreamSubscription<Object?>? _frames;
  Future<bool>? _connecting;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  /// Set once a socket has opened: from then on a drop reconnects on its
  /// own. Before that, a failed connect waits for the next mic press.
  bool _sessionWanted = false;

  /// The server rejected the token (`auth_failed`); don't reconnect.
  bool _rejected = false;

  StreamSubscription<Uint8List>? _mic;
  Completer<void>? _micDone;
  final _micBuffer = BytesBuilder(copy: false);
  bool _starting = false;

  /// Drops the rest of a reply the driver talked over, until `reply_done`
  /// or the driver's next transcript.
  bool _muted = false;

  /// Frees push-to-talk if the co-rider goes quiet mid-turn: no answer at
  /// all, or no `reply_done` after a tool turn's first reply.
  Timer? _answerWatchdog;

  /// A `screen_navigate: map` waiting to see whether a `map_route` follows
  /// it. Route tools send the two back to back; alone, it means "show me
  /// where I am" (the `show_screen` tool), so the map follows the driver.
  Timer? _mapFocusTimer;

  static const _backoff = [1, 2, 4, 8, 16];
  static const _answerTimeout = Duration(seconds: 20);
  static const _routeGrace = Duration(milliseconds: 300);

  /// End-of-turn padding: the backend ends a turn on voice-activity
  /// detection (no `ptt_release` yet, contract open item 1), which needs to
  /// hear silence after the driver stops.
  static const _trailingSilenceFrames = 16; // ~800 ms

  PushToTalkNotifier get _ptt => _ref.read(pushToTalkProvider.notifier);
  PushToTalkState get _pttState => _ref.read(pushToTalkProvider);
  VoicePlayback get _playback => _ref.read(voicePlaybackProvider);
  VoiceRecorder get _recorder => _ref.read(voiceRecorderProvider);

  /// The push-to-talk button's tap, per its state.
  Future<void> onPushToTalk() async {
    switch (_pttState) {
      case PushToTalkState.idle:
        await startTalking();
      case PushToTalkState.recording:
        await stopTalking();
      case PushToTalkState.processing:
        return; // Working on the last turn; nothing to do.
      case PushToTalkState.speaking:
        // Barge in: cut the co-rider off and listen.
        _muted = true;
        await _playback.stop();
        _ptt.set(PushToTalkState.idle);
        await startTalking();
    }
  }

  /// Opens the socket if needed, then streams the mic until [stopTalking].
  Future<void> startTalking() async {
    if (_starting || _mic != null) return;
    _starting = true;
    try {
      if (!await _recorder.ensurePermission()) {
        _setIssue(
          'VoiceOps needs the microphone to hear you. Allow it in Settings.',
        );
        return;
      }
      _ptt.set(PushToTalkState.processing); // while the socket opens
      if (!await _ensureConnected() || !mounted) {
        if (mounted) _ptt.set(PushToTalkState.idle);
        return;
      }
      final audio = await _recorder.start();
      _micBuffer.clear();
      final done = _micDone = Completer<void>();
      _mic = audio.listen(
        _onMic,
        onError: (Object e) => debugPrint('Mic stream failed: $e'),
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      _answerWatchdog?.cancel();
      _ptt.set(PushToTalkState.recording);
    } catch (e) {
      debugPrint('Could not start the mic: $e');
      if (mounted) {
        _setIssue("Couldn't start the microphone. Try again.");
        _ptt.set(PushToTalkState.idle);
      }
    } finally {
      _starting = false;
    }
  }

  /// Stops the mic; push-to-talk waits in `processing` for the reply.
  Future<void> stopTalking() async {
    final mic = _mic;
    if (mic == null) return;
    _ptt.set(PushToTalkState.processing);
    await _stopMic();
    final socket = _socket;
    if (socket == null) {
      _ptt.set(PushToTalkState.idle);
      return;
    }
    final silence = Uint8List(voiceFrameBytes);
    for (var i = 0; i < _trailingSilenceFrames; i++) {
      socket.sendAudio(silence);
    }
    _armWatchdog();
  }

  /// Asks the backend to hang up [callId] (the call overlay's end button).
  /// False when the socket is down and the request couldn't be sent.
  bool endCall(String callId) {
    final socket = _socket;
    if (socket == null || state.connection != VoiceConnection.connected) {
      return false;
    }
    socket.sendText(jsonEncode({'event': 'end_call', 'call_id': callId}));
    return true;
  }

  /// Hides the current issue (the banner's dismiss).
  void dismissIssue() =>
      state = VoiceSessionState(connection: state.connection);

  /// Closes the session on purpose (sign-out). The next mic press opens a
  /// new one.
  Future<void> disconnect() async {
    _sessionWanted = false;
    _reconnectTimer?.cancel();
    _answerWatchdog?.cancel();
    await _stopMic();
    _closeSocket();
    await _playback.stop();
    if (!mounted) return;
    _ptt.set(PushToTalkState.idle);
    state = const VoiceSessionState();
  }

  // ── Mic ──────────────────────────────────────────────────────────────

  void _onMic(Uint8List chunk) {
    _micBuffer.add(chunk);
    if (_micBuffer.length < voiceFrameBytes) return;
    final bytes = _micBuffer.takeBytes();
    var offset = 0;
    for (
      ;
      offset + voiceFrameBytes <= bytes.length;
      offset += voiceFrameBytes
    ) {
      _socket?.sendAudio(
        Uint8List.sublistView(bytes, offset, offset + voiceFrameBytes),
      );
    }
    if (offset < bytes.length) {
      _micBuffer.add(Uint8List.sublistView(bytes, offset));
    }
  }

  Future<void> _stopMic() async {
    final mic = _mic;
    if (mic == null) return;
    try {
      await _recorder.stop();
      // Let the last chunks the recorder already produced arrive.
      await _micDone?.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('Mic stop failed: $e');
    }
    // Not awaited: the stream is already done, and a subscription's cancel
    // future can outlive the zone that asked (fake time in tests).
    unawaited(mic.cancel());
    _mic = null;
    if (_micBuffer.isNotEmpty) _socket?.sendAudio(_micBuffer.takeBytes());
  }

  // ── Socket ───────────────────────────────────────────────────────────

  Future<bool> _ensureConnected() {
    if (_socket != null && state.connection == VoiceConnection.connected) {
      return Future.value(true);
    }
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<bool> _connect() async {
    _reconnectTimer?.cancel();
    final base = _ref.read(backendUriProvider);
    final token = _ref.read(authRepositoryProvider).accessToken;
    if (base == null || token == null) {
      _fail(
        base == null
            ? BackendConfig.notConfiguredMessage
            : 'Sign in again to talk to your co-rider.',
      );
      return false;
    }
    if (state.connection != VoiceConnection.reconnecting) {
      state = VoiceSessionState(
        connection: VoiceConnection.connecting,
        issue: state.issue,
      );
    }

    final String shiftId;
    try {
      shiftId = await _ref.read(shiftProvider.notifier).ensureStarted();
    } on ApiException catch (e) {
      _fail(e.message);
      return false;
    }
    if (!mounted) return false;

    _rejected = false;
    final socket = _ref.read(voiceSocketConnectorProvider)(
      voiceSocketUri(base, shiftId),
      {'Authorization': 'Bearer $token'},
    );
    _socket = socket;
    _frames = socket.frames.listen(
      _onFrame,
      onError: (Object e) => debugPrint('Voice socket error: $e'),
      onDone: () => _onSocketClosed(socket),
    );
    try {
      await socket.ready;
    } catch (e) {
      debugPrint('Voice socket failed to open: $e');
      await _dropSocket(socket);
      return false;
    }
    if (!mounted || _socket != socket) return false;
    _sessionWanted = true;
    _reconnectAttempt = 0;
    state = const VoiceSessionState(connection: VoiceConnection.connected);
    return true;
  }

  void _onSocketClosed(VoiceSocket socket) {
    if (_socket != socket) return; // an old socket, already replaced
    _dropSocket(socket);
  }

  /// A socket closed or failed to open: reconnect with backoff, or report.
  Future<void> _dropSocket(VoiceSocket socket) async {
    if (_socket != socket) return;
    _socket = null;
    unawaited(_frames?.cancel());
    _frames = null;
    _answerWatchdog?.cancel();
    await _stopMic();
    if (!mounted) return;
    // No reply_done can arrive on a closed socket, so nothing else would
    // free push-to-talk.
    _ptt.set(PushToTalkState.idle);

    if (_rejected) {
      state = VoiceSessionState(
        connection: VoiceConnection.failed,
        issue: state.issue,
      );
    } else if (_sessionWanted && _reconnectAttempt < _backoff.length) {
      final delay = Duration(seconds: _backoff[_reconnectAttempt++]);
      state = const VoiceSessionState(
        connection: VoiceConnection.reconnecting,
        issue: 'Voice dropped. Reconnecting to your co-rider…',
      );
      _reconnectTimer = Timer(delay, () {
        if (mounted) _ensureConnected();
      });
    } else {
      _sessionWanted = false;
      _fail("Can't reach your co-rider. Tap the mic to try again.");
    }
  }

  /// Closes the socket without waiting on the close handshake.
  void _closeSocket() {
    final socket = _socket;
    _socket = null;
    unawaited(_frames?.cancel());
    _frames = null;
    unawaited(socket?.close());
  }

  void _fail(String issue) {
    if (!mounted) return;
    state = VoiceSessionState(connection: VoiceConnection.failed, issue: issue);
  }

  void _setIssue(String issue) =>
      state = VoiceSessionState(connection: state.connection, issue: issue);

  // ── Incoming ─────────────────────────────────────────────────────────

  void _onFrame(Object? frame) {
    if (!mounted) return;
    if (_pttState case PushToTalkState.processing || PushToTalkState.speaking) {
      _armWatchdog();
    }
    if (frame is String) {
      _onText(frame);
    } else if (frame is List<int>) {
      _onAudio(frame is Uint8List ? frame : Uint8List.fromList(frame));
    }
  }

  void _onText(String text) {
    final VoiceEvent? event;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return;
      event = VoiceEvent.parse(json);
    } on FormatException catch (e) {
      debugPrint('Ignoring malformed voice event: $e');
      return;
    }
    if (event != null) _dispatch(event);
  }

  void _dispatch(VoiceEvent event) {
    if (_mapFocusTimer != null && event is! MapRouteEvent) _followDriver();
    switch (event) {
      case AgentStateEvent(:final state):
        _ref.read(agentStateProvider.notifier).setFromKey(state);
      case ScreenNavigateEvent(:final screen):
        _ref.read(navigationProvider).navigateForAgent(screen);
        if (screen == 'map') _mapFocusTimer = Timer(_routeGrace, _followDriver);
      case TaskStepEvent(:final step, :final status):
        _ref.read(taskProgressProvider.notifier).applyStep(step, status);
      case MapRouteEvent(:final route):
        _mapFocusTimer?.cancel();
        _mapFocusTimer = null;
        _ref.read(mapRouteProvider.notifier).show(route);
        _ref.read(mapFocusProvider.notifier).frameRoute();
      case CallStartedEvent():
        _ref.read(activeCallProvider.notifier).start(event);
      case CallEndedEvent(:final callId):
        _ref.read(activeCallProvider.notifier).end(callId);
      case SummaryChunkEvent(:final text, :final isFinal):
        _ref
            .read(summaryStreamProvider.notifier)
            .append(text, isFinal: isFinal);
      case TranscriptEvent(:final role, :final text):
        _ref.read(transcriptProvider.notifier).add(role, text);
        // The driver's next turn: whatever they talked over has ended, even
        // if its reply_done never came (a tool turn's first reply has none).
        if (role == SpeakerRole.driver) _muted = false;
      case ReplyDoneEvent():
        _onReplyDone();
      case ErrorEvent():
        _onError(event);
    }
  }

  void _onAudio(Uint8List pcm) {
    if (_muted) return;
    _playback.add(pcm);
    if (_pttState != PushToTalkState.recording) {
      _ptt.set(PushToTalkState.speaking);
    }
  }

  void _followDriver() {
    _mapFocusTimer?.cancel();
    _mapFocusTimer = null;
    if (mounted) _ref.read(mapFocusProvider.notifier).followDriver();
  }

  void _onReplyDone() {
    _answerWatchdog?.cancel();
    if (!_muted) _playback.flush();
    _muted = false;
    if (state.issue != null) {
      state = VoiceSessionState(connection: state.connection);
    }
    if (_pttState case PushToTalkState.processing || PushToTalkState.speaking) {
      _ptt.set(PushToTalkState.idle);
    }
  }

  void _onError(ErrorEvent error) {
    if (error.isFatal) _rejected = true;
    _setIssue(
      error.message.isNotEmpty
          ? error.message
          : 'Your co-rider hit a problem. Try again.',
    );
    if (_pttState == PushToTalkState.processing) {
      _answerWatchdog?.cancel();
      _ptt.set(PushToTalkState.idle);
    }
  }

  void _armWatchdog() {
    _answerWatchdog?.cancel();
    _answerWatchdog = Timer(_answerTimeout, () {
      if (!mounted) return;
      switch (_pttState) {
        case PushToTalkState.processing:
          _ptt.set(PushToTalkState.idle);
          _setIssue("Your co-rider didn't answer. Try again.");
        case PushToTalkState.speaking:
          // It answered but never closed the turn: just free the button.
          _ptt.set(PushToTalkState.idle);
        case PushToTalkState.idle || PushToTalkState.recording:
          break;
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _reconnectTimer?.cancel();
    _answerWatchdog?.cancel();
    _mapFocusTimer?.cancel();
    _mic?.cancel();
    _frames?.cancel();
    _socket?.close();
    super.dispose();
  }
}
