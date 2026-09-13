import '../../features/map/data/map_route.dart';
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
      'reply_done' => const ReplyDoneEvent(),
      'error' => ErrorEvent(
        code: field('code'),
        message: json['message'] as String? ?? '',
      ),
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
  const TaskStepEvent(this.step, this.status);
  final String step;
  final TaskStepStatus status;
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
  const ReplyDoneEvent();
}

/// `code` ∈ `auth_failed | session_expired | upstream_unavailable |
/// upstream_timeout | invalid_message | internal`; [message] is safe to show.
class ErrorEvent extends VoiceEvent {
  const ErrorEvent({required this.code, required this.message});
  final String code;
  final String message;

  /// The token was rejected, so reconnecting won't help. `session_expired`
  /// is not fatal: the next connect sends Supabase's refreshed token.
  bool get isFatal => code == 'auth_failed';
}
