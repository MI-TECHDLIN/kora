import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/voiceops_api.dart';
import '../features/map/data/location_source.dart';
import 'location_provider.dart';
import 'shift_provider.dart';
import 'voice_session_provider.dart';

/// How often the app posts the driver's position while the voice session is
/// up. `POST /v1/locations/ping` is the only thing that runs the backend's
/// risk engine, so this interval is also the resolution of every proactive
/// alert: the idle check needs five consecutive stationary pings, which at
/// this cadence is ~75 seconds, not the "over 5 minutes" its message claims.
/// Backend handoff §7 Q3 owns squaring the two.
const locationPingInterval = Duration(seconds: 15);

/// The GPS ping loop (`PROACTIVE_ALERT` link A). Kept out of [VoiceSession]
/// on purpose: the session owns the socket, this owns telemetry, and a
/// failed ping must never disturb a conversation.
final locationPingerProvider = Provider<LocationPinger>((ref) {
  final pinger = LocationPinger(ref);
  ref.onDispose(pinger.dispose);
  return pinger;
});

/// Posts the driver's position every [locationPingInterval] while the voice
/// session is connected, the app is in front, and there is a fix to send.
///
/// Fire-and-forget by design: the app never shows a ping failure and never
/// retries one, because the next tick carries a fresher position anyway.
class LocationPinger {
  LocationPinger(this._ref) {
    _lifecycle = AppLifecycleListener(
      onStateChange: (lifecycle) => setForeground(switch (lifecycle) {
        AppLifecycleState.resumed || AppLifecycleState.inactive => true,
        AppLifecycleState.hidden ||
        AppLifecycleState.paused ||
        AppLifecycleState.detached => false,
      }),
    );
    // Shares the map's location stream rather than opening a second one.
    _ref.listen<AsyncValue<LocationFix>>(locationProvider, (_, fix) {
      _fix = fix.valueOrNull;
      _sync();
    }, fireImmediately: true);
    _ref.listen<VoiceSessionState>(
      voiceSessionProvider,
      (_, _) => _sync(),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  late final AppLifecycleListener _lifecycle;

  Timer? _timer;
  LocationFix? _fix;
  bool _foreground = true;
  bool _sending = false;

  /// Whether the ping loop is running right now. The session being up isn't
  /// enough on its own — see [_sync].
  @visibleForTesting
  bool get isPinging => _timer != null;

  /// Called by the app-lifecycle listener; public so tests can background
  /// the app without a platform message.
  @visibleForTesting
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _sync();
  }

  /// Starts or stops the loop to match the session, the app's lifecycle and
  /// whether there is a position worth sending.
  void _sync() {
    final connected =
        _ref.read(voiceSessionProvider).connection == VoiceConnection.connected;
    if (connected && _foreground && _fix != null) {
      if (_timer != null) return;
      _timer = Timer.periodic(locationPingInterval, (_) => _ping());
      // Don't make the risk engine wait a whole interval for its first fix.
      _ping();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _ping() async {
    final fix = _fix;
    // A ping slower than the interval would otherwise stack up behind itself.
    if (fix == null || _sending) return;
    _sending = true;
    try {
      await _ref
          .read(voiceOpsApiProvider)
          .sendLocationPing(
            LocationPing(
              latitude: fix.point.latitude,
              longitude: fix.point.longitude,
              // geolocator reports metres per second; the backend wants km/h.
              speedKmh: (fix.speed ?? 0) * 3.6,
              heading: fix.heading ?? 0,
              accuracyMetres: fix.accuracy ?? 0,
              shiftId: _ref.read(shiftProvider),
            ),
          );
    } catch (e) {
      debugPrint('Location ping failed: $e');
    } finally {
      _sending = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lifecycle.dispose();
  }
}

/// Keeps [locationPingerProvider] alive for the life of the app, the way
/// `MapWarmup` does for the map's sources. It renders nothing.
class LocationPingLoop extends ConsumerWidget {
  const LocationPingLoop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(locationPingerProvider);
    return child;
  }
}
