import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/audio/voice_playback.dart';
import 'package:voiceops/core/audio/voice_recorder.dart';
import 'package:voiceops/core/realtime/voice_socket.dart';
import 'package:voiceops/features/map/data/location_source.dart';
import 'package:voiceops/features/map/data/heading_source.dart';
import 'package:voiceops/features/map/widgets/openfreemap_layer.dart';
import 'package:voiceops/features/summary/data/shift_report.dart';
import 'package:voiceops/providers/co_rider_voice_provider.dart';
import 'package:voiceops/providers/location_provider.dart';
import 'package:voiceops/providers/map_style_provider.dart';
import 'package:voiceops/providers/notification_preferences_provider.dart';
import 'package:voiceops/providers/onboarding_provider.dart';
import 'package:voiceops/providers/heading_provider.dart';
import 'package:voiceops/providers/vehicle_mode_provider.dart';

/// Offline stand-ins for everything the voice session and the Map tab talk
/// to: no socket, no mic, no speaker, no HTTP, no GPS, no tiles.

/// One scripted voice socket. The test plays the server.
class FakeVoiceSocket implements VoiceSocket {
  FakeVoiceSocket(this.uri, this.headers, {bool opens = true}) {
    if (opens) {
      _ready.complete();
    } else {
      _ready.completeError(const SocketFailure());
      _incoming.addError(const SocketFailure());
      _incoming.close();
    }
  }

  final Uri uri;
  final Map<String, String> headers;
  final _ready = Completer<void>();
  final _incoming = StreamController<Object?>();

  final sentText = <Map<String, dynamic>>[];
  final sentAudio = <Uint8List>[];
  bool closedByClient = false;

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<Object?> get frames => _incoming.stream;

  @override
  void sendText(String json) =>
      sentText.add(jsonDecode(json) as Map<String, dynamic>);

  @override
  void sendAudio(Uint8List pcm) => sentAudio.add(pcm);

  @override
  Future<void> close() async {
    closedByClient = true;
    await _incoming.close();
  }

  /// The server sends an event.
  void emit(Map<String, Object?> event) => _incoming.add(jsonEncode(event));

  /// The server sends co-rider audio.
  void emitAudio(Uint8List pcm) => _incoming.add(pcm);

  /// The connection drops from the server side.
  Future<void> drop() => _incoming.close();
}

class SocketFailure implements Exception {
  const SocketFailure();
}

/// Hands out [FakeVoiceSocket]s and remembers each one.
class FakeVoiceConnector {
  final sockets = <FakeVoiceSocket>[];

  /// While false, new sockets fail to open (backend down).
  bool serverUp = true;

  FakeVoiceSocket get last => sockets.last;

  VoiceSocket connect(Uri uri, Map<String, String> headers) {
    final socket = FakeVoiceSocket(uri, headers, opens: serverUp);
    sockets.add(socket);
    return socket;
  }
}

class FakeRecorder implements VoiceRecorder {
  /// Whether the mic was already allowed before anything asked.
  bool granted = false;

  /// The driver's answer when asked.
  bool permitted = true;
  int permissionRequests = 0;
  StreamController<Uint8List>? _mic;
  int starts = 0;

  bool get isRecording => _mic != null;

  /// The driver speaks: the mic produces [bytes].
  void speak(Uint8List bytes) => _mic!.add(bytes);

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return granted = permitted;
  }

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    return (_mic = StreamController<Uint8List>()).stream;
  }

  @override
  Future<void> stop() async {
    await _mic?.close();
    _mic = null;
  }

  @override
  Future<void> dispose() => stop();
}

class FakePlayback implements VoicePlayback {
  final played = <Uint8List>[];
  int flushes = 0;
  int stops = 0;

  @override
  void add(Uint8List pcm) => played.add(pcm);

  @override
  Future<void> flush() async => flushes++;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {}
}

class FakeVoiceOpsApi implements VoiceOpsApi {
  FakeVoiceOpsApi({this.profile, this.profileFailure});

  DriverProfile? profile;
  ApiException? profileFailure;
  ApiException? shiftFailure;
  int profileCalls = 0;
  int shiftCalls = 0;

  /// Every GPS ping the app has posted, in order.
  final pings = <LocationPing>[];

  /// Thrown by the next [sendLocationPing]; telemetry must shrug it off.
  ApiException? pingFailure;

  @override
  Future<DriverProfile> fetchDriverProfile() async {
    profileCalls++;
    if (profileFailure case final f?) throw f;
    return profile ?? const DriverProfile(id: 'driver-1');
  }

  @override
  Future<String> startShift() async {
    shiftCalls++;
    if (shiftFailure case final f?) throw f;
    return 'shift-1';
  }

  @override
  Future<void> sendLocationPing(LocationPing ping) async {
    pings.add(ping);
    if (pingFailure case final f?) throw f;
  }

  /// Returned by [fetchShiftReport]; null means "still processing".
  ShiftReport? report;

  /// Thrown by the next [fetchShiftReport] instead of returning [report].
  ApiException? reportFailure;

  /// Shift ids the app asked for a report on, in order.
  final reportRequests = <String>[];

  @override
  Future<ShiftReport?> fetchShiftReport(String shiftId) async {
    reportRequests.add(shiftId);
    if (reportFailure case final f?) throw f;
    return report;
  }
}

/// Streams fixes the test pushes; [problem] scripts a location problem.
class FakeLocationSource implements LocationSource {
  final _fixes = StreamController<LocationFix>.broadcast();
  LocationProblem? problem;
  final opened = <LocationProblem>[];
  int watches = 0;

  /// Whether location was already allowed before anything asked.
  bool granted = false;

  /// The driver's answer when asked.
  bool permitted = true;
  int permissionRequests = 0;

  void emit(LocationFix fix) => _fixes.add(fix);

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted = permitted;
  }

  @override
  Stream<LocationFix> watch() {
    watches++;
    if (problem case final p?) {
      return Stream.error(LocationUnavailable(p));
    }
    return _fixes.stream;
  }

  @override
  Future<void> openSettings(LocationProblem problem) async =>
      opened.add(problem);
}

class FakeHeadingSource implements HeadingSource {
  final _headings = StreamController<double>.broadcast();
  int watches = 0;

  void emit(double heading) => _headings.add(heading);

  @override
  Stream<double> watch() {
    watches++;
    return _headings.stream;
  }
}

class FakeVehicleModeStore implements VehicleModeStore {
  FakeVehicleModeStore([this.value]);

  VehicleMode? value;

  @override
  Future<VehicleMode?> load() async => value;

  @override
  Future<void> save(VehicleMode mode) async => value = mode;
}

class FakeMapStyleStore implements MapStyleStore {
  FakeMapStyleStore([this.value]);

  MapStyle? value;

  @override
  Future<MapStyle?> load() async => value;

  @override
  Future<void> save(MapStyle style) async => value = style;
}

class FakeNotificationPreferencesStore implements NotificationPreferencesStore {
  FakeNotificationPreferencesStore({
    bool proactiveAlertsEnabled = true,
    bool shiftSummaryReadyEnabled = true,
  }) : value = NotificationPreferences(
         proactiveAlertsEnabled: proactiveAlertsEnabled,
         shiftSummaryReadyEnabled: shiftSummaryReadyEnabled,
       );

  NotificationPreferences value;

  @override
  Future<NotificationPreferences> load() async => value;

  @override
  Future<void> saveProactiveAlerts({required bool enabled}) async {
    value = value.copyWith(proactiveAlertsEnabled: enabled);
  }

  @override
  Future<void> saveShiftSummaryReady({required bool enabled}) async {
    value = value.copyWith(shiftSummaryReadyEnabled: enabled);
  }
}

class FakeCoRiderVoiceStore implements CoRiderVoiceStore {
  FakeCoRiderVoiceStore([this.value]);

  CoRiderVoice? value;

  @override
  Future<CoRiderVoice?> load() async => value;

  @override
  Future<void> save(CoRiderVoice voice) async => value = voice;
}

class FakeOnboardingStore implements OnboardingStore {
  FakeOnboardingStore({this.completed = false});

  bool completed;

  @override
  Future<bool> load() async => completed;

  @override
  Future<void> save({required bool completed}) async =>
      this.completed = completed;
}

/// Everything a pumped app or screen needs to stay offline. Pass the fakes
/// a test wants to script; the rest are fresh defaults.
List<Override> offlineOverrides({
  FakeVoiceConnector? connector,
  FakeRecorder? recorder,
  FakePlayback? playback,
  FakeVoiceOpsApi? api,
  FakeLocationSource? location,
  FakeHeadingSource? heading,
  FakeVehicleModeStore? vehicleModeStore,
  FakeMapStyleStore? mapStyleStore,
  FakeNotificationPreferencesStore? notificationPreferencesStore,
  FakeCoRiderVoiceStore? coRiderVoiceStore,
  FakeOnboardingStore? onboardingStore,
  bool backendConfigured = true,
}) {
  final sockets = connector ?? FakeVoiceConnector();
  return [
    backendUriProvider.overrideWithValue(
      backendConfigured ? Uri.parse('https://api.voiceops.test') : null,
    ),
    voiceOpsApiProvider.overrideWithValue(api ?? FakeVoiceOpsApi()),
    voiceSocketConnectorProvider.overrideWithValue(sockets.connect),
    voiceRecorderProvider.overrideWithValue(recorder ?? FakeRecorder()),
    voicePlaybackProvider.overrideWithValue(playback ?? FakePlayback()),
    locationSourceProvider.overrideWithValue(location ?? FakeLocationSource()),
    headingSourceProvider.overrideWithValue(heading ?? FakeHeadingSource()),
    vehicleModeStoreProvider.overrideWithValue(
      vehicleModeStore ?? FakeVehicleModeStore(),
    ),
    mapStyleStoreProvider.overrideWithValue(
      mapStyleStore ?? FakeMapStyleStore(),
    ),
    notificationPreferencesStoreProvider.overrideWithValue(
      notificationPreferencesStore ?? FakeNotificationPreferencesStore(),
    ),
    coRiderVoiceStoreProvider.overrideWithValue(
      coRiderVoiceStore ?? FakeCoRiderVoiceStore(),
    ),
    baseMapLayerProvider.overrideWithValue(const SizedBox.shrink()),
    onboardingStoreProvider.overrideWithValue(
      onboardingStore ?? FakeOnboardingStore(),
    ),
  ];
}
