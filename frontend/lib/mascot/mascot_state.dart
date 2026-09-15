/// Maps directly to the co-rider's `CoRider` view-model triggers (see
/// [AgentStateX.riveKey] and docs/voiceops-corider-orb-rive-spec-v2.md).
enum AgentState {
  idle,
  thinking,
  speaking,
  calling,
  mapping,
  taskWorking,
  summarizing,
  celebrating,
}

extension AgentStateX on AgentState {
  String get riveKey {
    switch (this) {
      case AgentState.idle:
        return 'idle';
      case AgentState.thinking:
        return 'thinking';
      case AgentState.speaking:
        return 'speaking';
      case AgentState.calling:
        return 'calling';
      case AgentState.mapping:
        return 'mapping';
      case AgentState.taskWorking:
        return 'task';
      case AgentState.summarizing:
        return 'summarizing';
      case AgentState.celebrating:
        return 'celebrating';
    }
  }

  String? get label {
    switch (this) {
      case AgentState.idle:
        return null;
      case AgentState.thinking:
        return 'Thinking...';
      case AgentState.speaking:
        return 'Speaking...';
      case AgentState.calling:
        return 'Calling...';
      case AgentState.mapping:
        return 'Finding route...';
      case AgentState.taskWorking:
        return 'On it!';
      case AgentState.summarizing:
        return 'Summarizing...';
      case AgentState.celebrating:
        return 'All done!';
    }
  }
}
