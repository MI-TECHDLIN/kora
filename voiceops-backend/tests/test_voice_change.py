"""
Test voice change functionality for immediate voice updates.
"""
import pytest
from app.api.websocket import events
from app.agents.agent_config import resolve_voice, VOICES, DEFAULT_VOICE


def test_resolve_voice_valid():
    """Test that valid voice IDs pass through correctly."""
    assert resolve_voice("anna") == "anna"
    assert resolve_voice("ANNA") == "anna"  # Case insensitive
    assert resolve_voice("michael") == "michael"
    assert resolve_voice("MICHAEL") == "michael"


def test_resolve_voice_invalid():
    """Test that invalid voice IDs fall back to default."""
    assert resolve_voice("invalid_voice") == DEFAULT_VOICE
    assert resolve_voice("") == DEFAULT_VOICE
    assert resolve_voice(None) == DEFAULT_VOICE
    assert resolve_voice("ivy") == DEFAULT_VOICE  # Not in allowlist


def test_voice_allowlist():
    """Test that the voice allowlist contains expected voices."""
    expected_voices = {
        "alba", "eve", "george", "jane", "jean", "mary", "michael",  # American English
        "anna", "charles", "paul", "vera",  # British English
    }
    assert VOICES == expected_voices


def test_voice_change_accepted_event():
    """Test that voice_change_accepted event has correct structure."""
    event = events.voice_change_accepted("michael")
    assert event["event"] == "voice_change_accepted"
    assert event["voice"] == "michael"
    assert "message" in event
    assert "michael" in event["message"]


def test_voice_unchanged_event():
    """Test that voice_unchanged event has correct structure."""
    event = events.voice_unchanged("anna")
    assert event["event"] == "voice_unchanged"
    assert event["voice"] == "anna"
    assert "message" in event
    assert "anna" in event["message"]


def test_all_voices_in_allowlist():
    """Test that all common test voices are in the allowlist."""
    test_voices = ["anna", "michael", "jane", "george", "paul"]
    for voice in test_voices:
        assert voice in VOICES, f"{voice} should be in VOICES allowlist"


def test_default_voice_in_allowlist():
    """Test that the default voice is in the allowlist."""
    assert DEFAULT_VOICE in VOICES


if __name__ == "__main__":
    # Run basic validation
    print("Testing voice change functionality...")
    
    test_resolve_voice_valid()
    print("✓ Valid voice IDs resolve correctly")
    
    test_resolve_voice_invalid()
    print("✓ Invalid voice IDs fall back to default")
    
    test_voice_allowlist()
    print("✓ Voice allowlist is correct")
    
    test_voice_change_accepted_event()
    print("✓ voice_change_accepted event structure is correct")
    
    test_voice_unchanged_event()
    print("✓ voice_unchanged event structure is correct")
    
    test_all_voices_in_allowlist()
    print("✓ All test voices are in allowlist")
    
    test_default_voice_in_allowlist()
    print("✓ Default voice is in allowlist")
    
    print("\nAll voice change tests passed!")