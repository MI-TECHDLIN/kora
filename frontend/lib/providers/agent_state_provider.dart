import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../mascot/mascot_state.dart';

final agentStateProvider =
    StateNotifierProvider<AgentStateNotifier, AgentState>((ref) {
      return AgentStateNotifier();
    });

/// The co-rider's mood. Two sources feed it: the backend's `agent_state`
/// events (`thinking`, `mapping`, …) set the base mood, and the reply
/// audio actually playing overlays [AgentState.speaking] on top of it.
/// The backend has no `speaking` state yet — see
/// `docs/backend-handoff/agent-state-speaking.md`.
class AgentStateNotifier extends StateNotifier<AgentState> {
  AgentStateNotifier() : super(AgentState.idle);

  /// The mood last asked for, shown whenever no reply is playing.
  AgentState _base = AgentState.idle;
  bool _speaking = false;

  void setState(AgentState newState) {
    _base = newState;
    _apply();
  }

  void setFromKey(String key) {
    setState(
      AgentState.values.firstWhere(
        (s) => s.riveKey == key,
        orElse: () => AgentState.idle,
      ),
    );
  }

  /// The co-rider's reply audio started or stopped playing. While it
  /// plays, `speaking` wins over the base mood; when it stops the mood
  /// falls back to whatever the backend last set (or `idle`).
  void setSpeaking(bool speaking) {
    if (_speaking == speaking) return;
    _speaking = speaking;
    _apply();
  }

  void reset() {
    _speaking = false;
    setState(AgentState.idle);
  }

  void _apply() => state = _speaking ? AgentState.speaking : _base;
}
