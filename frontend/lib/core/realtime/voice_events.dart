import '../../features/map/data/map_route.dart';
import '../../features/summary/data/order_queue.dart';
import '../../providers/task_progress_provider.dart';

/// A server → client text frame on the voice socket. One class per event in
/// docs/contracts/interface.md §1; [VoiceEvent.parse] is the only decoder.
sealed class VoiceEvent {
  const VoiceEvent();

  /// Decodes one JSON frame. Returns null for an event this build doesn't
  /// know (new events are additive, so an older client skips them). Throws
  /// [FormatException] when a known event is missing a required field.
  static VoiceEvent? parse(Map<String, dynamic> json) {
    String field(String key) {
      final value = json[key];
      if (value is String) return value;
      throw FormatException('${json['event']}: missing "$key"', json);
    }

    return switch (json['event']) {
      'agent_state' => AgentStateEvent(field('state')),
      'screen_navigate' => ScreenNavigateEvent(field('screen')),
      'task_step' => TaskStepEvent(
        field('step'),
        TaskStepStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => TaskStepStatus.pending,
        ),
        reasoning: json['reasoning'] is String
            ? json['reasoning'] as String
            : null,
      ),
      'map_route' => MapRouteEvent(MapRoute.fromJson(json)),
      'call_started' => CallStartedEvent(
        callId: field('call_id'),
        deliveryId: json['delivery_id'] as String?,
        customerName: json['customer_name'] as String?,
        sequence: (json['sequence'] as num?)?.toInt(),
      ),
      'call_ended' => CallEndedEvent(field('call_id')),
      'summary_chunk' => SummaryChunkEvent(
        field('text'),
        isFinal: json['final'] == true,
      ),
      'transcript' => TranscriptEvent(
        role: json['role'] == 'driver' ? SpeakerRole.driver : SpeakerRole.agent,
        text: field('text'),
      ),
      'reply_done' => ReplyDoneEvent(interrupted: json['interrupted'] == true),
      'conversation_end' => const ConversationEndEvent(),
      'order_offer' => OrderOfferEvent(
        orderId: field('order_id'),
        area: field('area'),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        timeWindow: json['time_window'] as String?,
        packageCount: (json['package_count'] as num?)?.toInt(),
        expiresInSeconds: (json['expires_in_s'] as num?)?.toInt() ?? 0,
      ),
      'order_offer_closed' => OrderOfferClosedEvent(
        orderId: field('order_id'),
        outcome: OrderOfferOutcome.values.firstWhere(
          (outcome) => outcome.name == json['outcome'],
          orElse: () => throw FormatException(
            'order_offer_closed: invalid "outcome"',
            json,
          ),
        ),
      ),
      'PROACTIVE_ALERT' => ProactiveAlertEvent(
        message: field('message'),
        severity: RiskSeverity.parse(json['severity']),
        riskType: RiskType.parse(json['risk_type']),
        deliveryId: json['delivery_id'] as String?,
        routeSuggestion: RouteSuggestion.parse(
          json['route_suggestion'],
          deliveryId: json['delivery_id'] as String?,
        ),
      ),
      'error' => ErrorEvent(
        code: field('code'),
        message: json['message'] as String? ?? '',
      ),
      'queue_updated' => QueueUpdatedEvent(OrderQueue.fromJson(json)),
      'voice_change_accepted' => VoiceChangeAcceptedEvent(field('voice')),
      'voice_unchanged' => VoiceUnchangedEvent(field('voice')),
      _ => null,
    };
  }
}

/// `state` ∈ `AgentState.riveKey` values.
class AgentStateEvent extends VoiceEvent {
  const AgentStateEvent(this.state);
  final String state;
}

/// `screen` ∈ `MainTab` names.
class ScreenNavigateEvent extends VoiceEvent {
  const ScreenNavigateEvent(this.screen);
  final String screen;
}

class TaskStepEvent extends VoiceEvent {
  const TaskStepEvent(this.step, this.status, {this.reasoning});
  final String step;
  final TaskStepStatus status;
  final String? reasoning;
}

class MapRouteEvent extends VoiceEvent {
  const MapRouteEvent(this.route);
  final MapRoute route;
}

class CallStartedEvent extends VoiceEvent {
  const CallStartedEvent({
    required this.callId,
    this.deliveryId,
    this.customerName,
    this.sequence,
  });
  final String callId;
  final String? deliveryId;
  final String? customerName;
  final int? sequence;
}

class CallEndedEvent extends VoiceEvent {
  const CallEndedEvent(this.callId);
  final String callId;
}

class SummaryChunkEvent extends VoiceEvent {
  const SummaryChunkEvent(this.text, {required this.isFinal});
  final String text;
  final bool isFinal;
}

enum SpeakerRole { driver, agent }

class TranscriptEvent extends VoiceEvent {
  const TranscriptEvent({required this.role, required this.text});
  final SpeakerRole role;
  final String text;
}

class ReplyDoneEvent extends VoiceEvent {
  const ReplyDoneEvent({this.interrupted = false});

  final bool interrupted;
}

class ConversationEndEvent extends VoiceEvent {
  const ConversationEndEvent();
}

/// A time-boxed delivery offered to this driver. Privacy is deliberate:
/// before acceptance the server sends only [area], never the recipient or
/// full street address (docs/contracts/interface.md §1).
class OrderOfferEvent extends VoiceEvent {
  const OrderOfferEvent({
    required this.orderId,
    required this.area,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.timeWindow,
    required this.packageCount,
    required this.expiresInSeconds,
  });

  final String orderId;
  final String area;
  final double? latitude;
  final double? longitude;
  final double? distanceKm;
  final String? timeWindow;
  final int? packageCount;
  final int expiresInSeconds;
}

enum OrderOfferOutcome { accepted, declined, expired, withdrawn }

class OrderOfferClosedEvent extends VoiceEvent {
  const OrderOfferClosedEvent({required this.orderId, required this.outcome});

  final String orderId;
  final OrderOfferOutcome outcome;
}

/// What the risk engine flagged (`risk_type` on `PROACTIVE_ALERT`), mirroring
/// the backend's `RiskType`. An unrecognised value parses to [unknown] rather
/// than dropping the alert: the message still matters to the driver.
enum RiskType {
  lateDelivery('LATE_DELIVERY'),
  customerUnavailable('CUSTOMER_UNAVAILABLE'),
  excessiveIdle('EXCESSIVE_IDLE'),
  driverNoResponse('DRIVER_NO_RESPONSE'),
  timeWindowRisk('TIME_WINDOW_RISK'),
  routeDeviation('ROUTE_DEVIATION'),
  unknown('');

  const RiskType(this.wire);

  /// The value the backend sends.
  final String wire;

  static RiskType parse(Object? value) =>
      values.firstWhere((type) => type.wire == value, orElse: () => unknown);
}

/// How hard the risk engine is pushing (`severity` on `PROACTIVE_ALERT`).
enum RiskSeverity {
  low('LOW'),
  medium('MEDIUM'),
  high('HIGH'),
  critical('CRITICAL');

  const RiskSeverity(this.wire);
  final String wire;

  /// Unknown severities read as [medium] so an alert is never silently
  /// promoted to a red one or demoted out of sight.
  static RiskSeverity parse(Object? value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => medium);
}

/// The alternate route on a `ROUTE_DEVIATION` alert: the same drawable shape
/// as a `map_route`, plus the ETA it is being compared against.
class RouteSuggestion {
  const RouteSuggestion({
    required this.route,
    this.etaMinutes,
    this.currentEtaMinutes,
  });

  /// Reads `route_suggestion`. Null when the field is absent or null (every
  /// risk type but `ROUTE_DEVIATION`), or when it carries nothing usable.
  /// The geometry goes through [MapRoute.fromJson], so a geometry this build
  /// can't decode yields a route with no line instead of throwing.
  static RouteSuggestion? parse(Object? json, {String? deliveryId}) {
    if (json is! Map) return null;
    final eta = (json['eta_minutes'] as num?)?.toInt();
    final current = (json['current_eta_minutes'] as num?)?.toInt();
    final geometry = json['geometry'];
    final encoded = geometry is String ? geometry : '';
    if (eta == null && current == null && encoded.isEmpty) return null;
    return RouteSuggestion(
      route: MapRoute.fromJson({
        'delivery_id': deliveryId ?? '',
        'polyline': encoded,
        'summary': 'Suggested reroute',
        'duration_mins': ?eta,
        if (eta != null) 'duration_text': '$eta min',
      }),
      etaMinutes: eta,
      currentEtaMinutes: current,
    );
  }

  final MapRoute route;

  /// Drive time on the alternate route, in minutes.
  final int? etaMinutes;

  /// Drive time the driver is on course for now, in minutes.
  final int? currentEtaMinutes;

  /// Minutes the alternate saves, or null when the two ETAs don't say.
  int? get savingsMinutes {
    final alternate = etaMinutes;
    final current = currentEtaMinutes;
    if (alternate == null || current == null || current <= alternate) {
      return null;
    }
    return current - alternate;
  }
}

/// The risk engine speaking up unprompted: traffic on the route, a delivery
/// window about to slip, or the van standing still too long
/// (docs/contracts/interface.md §1). [message] is the sentence the co-rider
/// says, and is shown as well — audio alone can be missed.
class ProactiveAlertEvent extends VoiceEvent {
  const ProactiveAlertEvent({
    required this.message,
    required this.severity,
    required this.riskType,
    this.deliveryId,
    this.routeSuggestion,
  });

  final String message;
  final RiskSeverity severity;
  final RiskType riskType;

  /// The stop at risk, or null for a driver-level risk like idle time.
  final String? deliveryId;

  /// The faster way round, on `ROUTE_DEVIATION` only.
  final RouteSuggestion? routeSuggestion;
}

/// `code` ∈ `auth_failed | session_expired | upstream_unavailable |
/// upstream_timeout | invalid_message | internal | voice_not_configured`;
/// [message] is safe to show.
class ErrorEvent extends VoiceEvent {
  const ErrorEvent({required this.code, required this.message});
  final String code;
  final String message;

  /// Reconnecting won't help: the token was rejected (`auth_failed`), or the
  /// server has no voice provider set up (`voice_not_configured`).
  /// `session_expired` is not fatal: the next connect sends Supabase's
  /// refreshed token.
  bool get isFatal => code == 'auth_failed' || code == 'voice_not_configured';

  /// [message], or a sentence for [code] when the backend sent none.
  String get displayMessage {
    if (message.isNotEmpty) return message;
    return switch (code) {
      'auth_failed' => 'Sign in again to talk to your co-rider.',
      'session_expired' => 'Your session expired. Sign in again.',
      'voice_not_configured' =>
        "Kora's voice service isn't set up on the server yet.",
      'upstream_unavailable' =>
        'The voice service is unreachable. Try again in a moment.',
      'upstream_timeout' => 'The voice service is slow to answer. Try again.',
      _ => 'Your co-rider hit a problem. Try again.',
    };
  }
}

/// The backend took a `change_voice` request and is about to close the
/// socket so the app reconnects with the new voice.
class VoiceChangeAcceptedEvent extends VoiceEvent {
  const VoiceChangeAcceptedEvent(this.voice);
  final String voice;
}

/// The requested voice is already the session's voice; nothing reconnects.
class VoiceUnchangedEvent extends VoiceEvent {
  const VoiceUnchangedEvent(this.voice);
  final String voice;
}

/// The order queue or the daily target changed. The payload is the same
/// snapshot `GET /v1/shift/{shift_id}/queue` returns, so it replaces the
/// app's queue outright.
class QueueUpdatedEvent extends VoiceEvent {
  const QueueUpdatedEvent(this.queue);
  final OrderQueue queue;
}
