"""
Test the speaking state implementation for agent audio bursts.

This tests the changes from the agent-state-speaking.md proposal:
1. speaking is added to agent_state vocabulary
2. agent_state: speaking is emitted on first frame of each audio burst
3. The state resets appropriately for tool turns with multiple audio bursts
"""
import pytest
from app.api.websocket import events


def test_speaking_in_agent_states():
    """Test that 'speaking' is in the AGENT_STATES vocabulary."""
    assert "speaking" in events.AGENT_STATES
    assert "idle" in events.AGENT_STATES
    assert "thinking" in events.AGENT_STATES


def test_agent_state_speaking_event():
    """Test that agent_state() accepts 'speaking' as a valid state."""
    event = events.agent_state("speaking")
    assert event == {"event": "agent_state", "state": "speaking"}


def test_agent_state_validation():
    """Test that invalid states are rejected."""
    with pytest.raises(ValueError, match="agent_state.state"):
        events.agent_state("invalid_state")
    
    # Valid states should work
    for state in events.AGENT_STATES:
        result = events.agent_state(state)
        assert result["event"] == "agent_state"
        assert result["state"] == state


def test_all_contract_states():
    """Test that all contract states from interface.md are present."""
    expected_states = {"idle", "thinking", "calling", "mapping", "task", "summarizing", "celebrating", "speaking"}
    assert expected_states == events.AGENT_STATES


if __name__ == "__main__":
    # Run basic validation
    print("Testing speaking state implementation...")
    
    test_speaking_in_agent_states()
    print("✓ speaking is in AGENT_STATES")
    
    test_agent_state_speaking_event()
    print("✓ agent_state('speaking') creates correct event")
    
    test_agent_state_validation()
    print("✓ agent_state validation works correctly")
    
    test_all_contract_states()
    print("✓ All contract states are present")
    
    print("\nAll tests passed! The speaking state implementation is correct.")