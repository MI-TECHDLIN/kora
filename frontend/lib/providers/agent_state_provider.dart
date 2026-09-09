import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../mascot/mascot_state.dart';

final agentStateProvider =
    StateNotifierProvider<AgentStateNotifier, AgentState>((ref) {
      return AgentStateNotifier();
    });

class AgentStateNotifier extends StateNotifier<AgentState> {
  AgentStateNotifier() : super(AgentState.idle);

  void setState(AgentState newState) => state = newState;

  void setFromKey(String key) {
    state = AgentState.values.firstWhere(
      (s) => s.riveKey == key,
      orElse: () => AgentState.idle,
    );
  }

  void reset() => state = AgentState.idle;
}
