"""
Simple test to verify audio playback is working.
"""
import numpy as np
import pytest

try:
    import sounddevice as sd
except (ImportError, OSError) as exc:  # OSError: PortAudio library not found
    pytest.skip(f"sounddevice unavailable: {exc}", allow_module_level=True)

pytestmark = pytest.mark.audio

SAMPLE_RATE = 24000

def test_audio_playback():
    """Test basic audio playback"""
    print("Testing audio playback...")
    print(f"Sample rate: {SAMPLE_RATE}")
    print(f"Default output device: {sd.default.device}")
    
    # Generate a simple tone (1 second)
    duration = 1.0
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), False)
    tone = 0.5 * np.sin(2 * np.pi * 440 * t)  # 440 Hz sine wave
    audio = (tone * 32767).astype(np.int16)  # Convert to 16-bit PCM
    
    print(f"Generated tone: {len(audio)} samples")
    print("Playing tone...")
    
    try:
        sd.play(audio, SAMPLE_RATE)
        sd.wait()
        print("SUCCESS: Audio playback successful!")
        return True
    except Exception as e:
        print(f"ERROR: Audio playback failed: {e}")
        return False

if __name__ == "__main__":
    test_audio_playback()
