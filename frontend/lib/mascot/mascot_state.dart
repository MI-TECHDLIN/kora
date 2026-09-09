/// Maps directly to Rive State Machine string inputs — SDD v2.0 §6.
enum AgentState {
  idle,
  thinking,
  calling,
  mapping,
  taskWorking,
  translating,
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
      case AgentState.calling:
        return 'calling';
      case AgentState.mapping:
        return 'mapping';
      case AgentState.taskWorking:
        return 'task';
      case AgentState.translating:
        return 'translating';
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
      case AgentState.calling:
        return 'Calling...';
      case AgentState.mapping:
        return 'Finding route...';
      case AgentState.taskWorking:
        return 'On it!';
      case AgentState.translating:
        return 'Translating...';
      case AgentState.summarizing:
        return 'Summarizing...';
      case AgentState.celebrating:
        return 'All done!';
    }
  }
}
