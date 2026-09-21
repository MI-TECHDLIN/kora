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
import 'co_rider_voice_provider.dart';
import 'map_route_provider.dart';
import 'navigation_provider.dart';
import 'notification_preferences_provider.dart';
import 'order_offer_provider.dart';
import 'proactive_alert_provider.dart';
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

  /// The backend accepted a `change_voice` and is closing the socket on
  /// purpose: reconnect at once (`_connect` reads the saved voice), without
  /// the "voice dropped" banner.
  bool _switchingVoice = false;

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
  Timer? _idleTimer;

  /// A `screen_navigate: map` waiting to see whether a `map_route` follows
  /// it. Route tools send the two back to back; alone, it means "show me
  /// where I am" (the `show_screen` tool), so the map follows the driver.
  Timer? _mapFocusTimer;

  static const _backoff = [1, 2, 4, 8, 16];
  static const _answerTimeout = Duration(seconds: 20);
  static const _routeGrace = Duration(milliseconds: 300);
  static const idleTimeout = Duration(seconds: 10);
  static const _speechRms = 500;

  /// End-of-turn padding: the backend ends a turn on voice-activity
  /// detection (no `ptt_release` yet, contract open item 1), which needs to
  /// hear silence after the driver stops.
  static const _trailingSilenceFrames = 16; // ~800 ms

  PushToTalkNotifier get _ptt => _ref.read(pushToTalkProvider.notifier);
  PushToTalkState get _pttState => _ref.read(pushToTalkProvider);
  VoicePlayback get _playback => _ref.read(voicePlaybackProvider);
  VoiceRecorder get _recorder => _ref.read(voiceRecorderProvider);

  bool get _micOpen => _mic != null;

  /// Moves push-to-talk, and mirrors its `speaking` onto the co-rider's
  /// mood. The backend has no `speaking` agent_state yet (see
  /// docs/backend-handoff/agent-state-speaking.md), so the orb takes it
  /// from the reply audio that is actually playing. Every other mood
  /// still comes from the backend, and returns once the reply ends.
  void _setPtt(PushToTalkState next) {
    _ptt.set(next);
    _ref
        .read(agentStateProvider.notifier)
        .setSpeaking(next == PushToTalkState.speaking);
  }

  /// The push-to-talk button's tap, per its state.
  Future<void> onPushToTalk() async {
    switch (_pttState) {
      case PushToTalkState.idle:
        await startConversation();
      case PushToTalkState.recording:
        await endConversation();
      case PushToTalkState.processing:
        if (_micOpen) await endConversation();
      case PushToTalkState.speaking:
        // Barge in: cut the co-rider off and listen.
        _muted = true;
        await _playback.stop();
        if (_micOpen) {
          _setPtt(PushToTalkState.recording);
          _armIdle();
        } else {
          _setPtt(PushToTalkState.idle);
          await startConversation();
        }
    }
  }

  /// Opens the socket and keeps the mic live for the conversation.
  Future<void> startConversation() async {
    if (_starting || _micOpen) return;
    _starting = true;
    try {
      if (!await _recorder.ensurePermission()) {
        _setIssue(
          'VoiceOps needs the microphone to hear you. Allow it in Settings.',
        );
        return;
      }
      _setPtt(PushToTalkState.processing); // while the socket opens
      if (!await _ensureConnected() || !mounted) {
        if (mounted) _setPtt(PushToTalkState.idle);
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
      _ref.read(micLiveProvider.notifier).state = true;
      if (_pttState != PushToTalkState.speaking) {
        _answerWatchdog?.cancel();
        _setPtt(PushToTalkState.recording);
        _armIdle();
      }
    } catch (e) {
      debugPrint('Could not start the mic: $e');
      if (mounted) {
        _setIssue("Couldn't start the microphone. Try again.");
        _setPtt(PushToTalkState.idle);
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> startTalking() => startConversation();

  Future<void> stopTalking() => endConversation();

  /// Stops the mic and ends the current continuous conversation.
  Future<void> endConversation() async {
    final mic = _mic;
    if (mic == null) return;
    _idleTimer?.cancel();
    if (_pttState == PushToTalkState.recording) _setPtt(PushToTalkState.idle);
    await _stopMic();
    final socket = _socket;
    if (socket == null) {
      _setPtt(PushToTalkState.idle);
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

  /// Answers the visible order card over the existing voice WebSocket.
  /// The backend invokes the same tool handler as a spoken answer, without
  /// asking AssemblyAI to interpret a synthetic voice turn.
  bool respondToOrderOffer(String orderId, {required bool accept}) {
    final socket = _socket;
    if (socket == null || state.connection != VoiceConnection.connected) {
      _setIssue("Voice is offline, so the order couldn't be answered.");
      return false;
    }
    _ref.read(orderOfferProvider.notifier).markResponding(orderId);
    socket.sendText(
      jsonEncode({
        'event': accept ? 'accept_order' : 'decline_order',
        'order_id': orderId,
      }),
    );
    return true;
  }

  /// Tells a live session to switch to [voice] (docs/frontend-voice-change-guide.md).
  /// The caller has already saved it to `coRiderVoiceProvider`, which every
  /// new connection reads, so with no live socket there is nothing to do. On
  /// a live one, the backend answers `voice_change_accepted` and closes, and
  /// the reconnect opens with the new voice.
  bool applyVoice(CoRiderVoice voice) {
    final socket = _socket;
    if (socket == null || state.connection != VoiceConnection.connected) {
      return false;
    }
    socket.sendText(jsonEncode({'event': 'change_voice', 'voice': voice.name}));
    return true;
  }

  /// Hides the current issue (the banner's dismiss).
  void dismissIssue() =>
      state = VoiceSessionState(connection: state.connection);

  /// Closes the session on purpose (sign-out). The next mic press opens a
  /// new one.
  Future<void> disconnect() async {
    _sessionWanted = false;
    _switchingVoice = false;
    _reconnectTimer?.cancel();
    _answerWatchdog?.cancel();
    _idleTimer?.cancel();
    await _stopMic();
    _closeSocket();
    await _playback.stop();
    if (!mounted) return;
    _ref.read(orderOfferProvider.notifier).clear();
    _ref.read(proactiveAlertProvider.notifier).dismiss();
    _ref.read(taskProgressProvider.notifier).clear();
    _setPtt(PushToTalkState.idle);
    state = const VoiceSessionState();
  }

  // ── Mic ──────────────────────────────────────────────────────────────

  void _onMic(Uint8List chunk) {
    if (_pttState == PushToTalkState.recording && _loud(chunk)) _armIdle();
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
    if (mounted) _ref.read(micLiveProvider.notifier).state = false;
    if (_micBuffer.isNotEmpty) _socket?.sendAudio(_micBuffer.takeBytes());
  }

  static bool _loud(Uint8List chunk) {
    final samples = chunk.length ~/ 2;
    if (samples == 0) return false;
    final data = ByteData.sublistView(chunk);
    var sum = 0.0;
    for (var i = 0; i < samples; i++) {
      final sample = data.getInt16(i * 2, Endian.little);
      sum += sample * sample;
    }
    return sum / samples >= _speechRms * _speechRms;
  }

  void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      if (mounted && _micOpen && _pttState == PushToTalkState.recording) {
        unawaited(endConversation());
      }
    });
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

    final voices = _ref.read(coRiderVoiceProvider.notifier);
    await voices.loaded;
    if (!mounted) return false;

    _rejected = false;
    final socket = _ref.read(voiceSocketConnectorProvider)(
      voiceSocketUri(
        base,
        shiftId,
        voice: _ref.read(coRiderVoiceProvider).name,
      ),
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
    // The backend immediately reassigns an offer when this socket leaves.
    // A reconnect will receive it again if this driver still owns it.
    _ref.read(orderOfferProvider.notifier).clear();
    // No reply_done can arrive on a closed socket, so nothing else would
    // free push-to-talk.
    _setPtt(PushToTalkState.idle);

    if (_rejected) {
      state = VoiceSessionState(
        connection: VoiceConnection.failed,
        issue: state.issue,
      );
    } else if (_switchingVoice && _sessionWanted) {
      _switchingVoice = false;
      state = const VoiceSessionState(connection: VoiceConnection.reconnecting);
      _reconnectTimer = Timer(Duration.zero, () {
        if (mounted) _ensureConnected();
      });
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
        final notifications = _ref.read(notificationPreferencesProvider);
        if (screen != 'summary' || notifications.shiftSummaryReadyEnabled) {
          _ref.read(navigationProvider).navigateForAgent(screen);
          if (screen == 'map') {
            _mapFocusTimer = Timer(_routeGrace, _followDriver);
          }
        }
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
        if (role == SpeakerRole.driver) _onDriverTurn();
      case ReplyDoneEvent(:final interrupted):
        _onReplyDone(interrupted: interrupted);
      case ConversationEndEvent():
        unawaited(endConversation());
        _setPtt(PushToTalkState.idle);
      case OrderOfferEvent():
        _ref.read(orderOfferProvider.notifier).show(event);
      case OrderOfferClosedEvent(:final orderId, :final outcome):
        _ref.read(orderOfferProvider.notifier).close(orderId, outcome);
      case ProactiveAlertEvent():
        _onProactiveAlert(event);
      case ErrorEvent():
        _onError(event);
      case VoiceChangeAcceptedEvent():
        _switchingVoice = true;
      case VoiceUnchangedEvent():
        break;
    }
  }

  /// The risk engine flagged something. Show the sentence (the co-rider
  /// says it too, but audio can be missed), and when it comes with a faster
  /// way round, draw that on the map so "want me to reroute?" has something
  /// to point at.
  void _onProactiveAlert(ProactiveAlertEvent alert) {
    if (!_ref.read(notificationPreferencesProvider).proactiveAlertsEnabled) {
      return;
    }
    _ref.read(proactiveAlertProvider.notifier).show(alert);
    final route = alert.routeSuggestion?.route;
    // An undrawable geometry leaves the map on the current route rather
    // than blanking it.
    if (route == null || route.line.isEmpty) return;
    _mapFocusTimer?.cancel();
    _mapFocusTimer = null;
    _ref.read(mapRouteProvider.notifier).show(route);
    _ref.read(mapFocusProvider.notifier).frameRoute();
  }

  void _onAudio(Uint8List pcm) {
    if (_muted) return;
    _playback.add(pcm);
    if (_pttState != PushToTalkState.speaking) {
      _idleTimer?.cancel();
      _setPtt(PushToTalkState.speaking);
    }
  }

  void _onDriverTurn() {
    _muted = false;
    if (_micOpen && _pttState == PushToTalkState.recording) {
      _idleTimer?.cancel();
      _setPtt(PushToTalkState.processing);
      _armWatchdog();
    }
  }

  void _followDriver() {
    _mapFocusTimer?.cancel();
    _mapFocusTimer = null;
    if (mounted) _ref.read(mapFocusProvider.notifier).followDriver();
  }

  void _onReplyDone({required bool interrupted}) {
    _answerWatchdog?.cancel();
    _idleTimer?.cancel();
    if (interrupted) {
      unawaited(_playback.stop());
    } else if (!_muted) {
      _playback.flush();
    }
    _muted = false;
    if (state.issue != null) {
      state = VoiceSessionState(connection: state.connection);
    }
    if (_pttState case PushToTalkState.processing || PushToTalkState.speaking) {
      if (_micOpen) {
        _setPtt(PushToTalkState.recording);
        _armIdle();
      } else {
        _setPtt(PushToTalkState.idle);
      }
    }
  }

  void _onError(ErrorEvent error) {
    if (error.isFatal) _rejected = true;
    _ref.read(orderOfferProvider.notifier).responseFailed();
    _setIssue(
      error.message.isNotEmpty
          ? error.message
          : 'Your co-rider hit a problem. Try again.',
    );
    if (_pttState == PushToTalkState.processing) {
      _answerWatchdog?.cancel();
      if (_micOpen) {
        _setPtt(PushToTalkState.recording);
        _armIdle();
      } else {
        _setPtt(PushToTalkState.idle);
      }
    }
  }

  void _armWatchdog() {
    _answerWatchdog?.cancel();
    _idleTimer?.cancel();
    _answerWatchdog = Timer(_answerTimeout, () {
      if (!mounted) return;
      switch (_pttState) {
        case PushToTalkState.processing:
          if (_micOpen) {
            _setPtt(PushToTalkState.recording);
            _armIdle();
          } else {
            _setPtt(PushToTalkState.idle);
          }
          _setIssue("Your co-rider didn't answer. Try again.");
        case PushToTalkState.speaking:
          // It answered but never closed the turn: just free the button.
          if (_micOpen) {
            _setPtt(PushToTalkState.recording);
            _armIdle();
          } else {
            _setPtt(PushToTalkState.idle);
          }
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
    _idleTimer?.cancel();
    _mapFocusTimer?.cancel();
    _mic?.cancel();
    _frames?.cancel();
    _socket?.close();
    super.dispose();
  }
}
