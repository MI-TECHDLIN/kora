"""
Audio utility functions for recording, resampling, and audio processing.
"""
import numpy as np
import struct
import wave
from typing import Tuple


def save_wav(audio_bytes: bytes, wav_path: str, sample_rate: int) -> None:
    """Save PCM16 audio bytes as a WAV file."""
    # Create WAV header
    data_size = len(audio_bytes)
    header = b'RIFF'
    header += struct.pack('<I', 36 + data_size)
    header += b'WAVE'
    header += b'fmt '
    header += struct.pack('<I', 16)
    header += struct.pack('<H', 1)  # PCM
    header += struct.pack('<H', 1)  # mono
    header += struct.pack('<I', sample_rate)
    header += struct.pack('<I', sample_rate * 2)
    header += struct.pack('<H', 2)
    header += struct.pack('<H', 16)
    header += b'data'
    header += struct.pack('<I', data_size)

    with open(wav_path, 'wb') as f:
        f.write(header)
        f.write(audio_bytes)


def resample_audio(pcm16_bytes: bytes, source_rate: int, target_rate: int) -> bytes:
    """Resample PCM16 audio from source_rate to target_rate using numpy."""
    if source_rate == target_rate:
        return pcm16_bytes
    
    # Convert bytes to int16 array
    audio_array = np.frombuffer(pcm16_bytes, dtype=np.int16)
    
    # Calculate resampling ratio
    ratio = target_rate / source_rate
    new_length = int(len(audio_array) * ratio)
    
    # Use linear interpolation for resampling
    indices = np.linspace(0, len(audio_array) - 1, new_length)
    resampled = np.interp(indices, np.arange(len(audio_array)), audio_array).astype(np.int16)
    
    return resampled.tobytes()


def read_wav_file(wav_path: str) -> Tuple[bytes, int, int, int]:
    """Read WAV file and return PCM data, channels, sample width, and frame rate."""
    with wave.open(wav_path, "rb") as w:
        channels = w.getnchannels()
        sampwidth = w.getsampwidth()
        framerate = w.getframerate()
        pcm_data = w.readframes(w.getnframes())
    return pcm_data, channels, sampwidth, framerate