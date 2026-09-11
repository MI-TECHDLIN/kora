"""
Live interaction with AssemblyAI Voice Agent.
Records microphone input in real-time and streams it to the API.
Plays the agent's response automatically.
"""
import sounddevice as sd
import numpy as np
import requests
import json
import base64
import struct
from datetime import datetime

# Configuration
SAMPLE_RATE = 24000  # AssemblyAI requires 24 kHz
CHUNK_MS = 50  # 50ms chunks
CHUNK_SIZE = (SAMPLE_RATE * 2 * CHUNK_MS) // 1000  # 2400 bytes
DURATION = 5  # seconds to record
API_URL = "http://localhost:8000/v1/voice-agent"

print("=" * 60)
print("LIVE INTERACTION WITH ASSEMBLYAI VOICE AGENT")
print("=" * 60)
print(f"\nRecording for {DURATION} seconds at {SAMPLE_RATE} Hz...")
print("Speak clearly into your microphone now.")

# Record audio
recording = sd.rec(int(DURATION * SAMPLE_RATE), 
                   samplerate=SAMPLE_RATE, 
                   channels=1,
                   dtype='int16')
sd.wait()  # Wait until recording is finished

print("Recording complete.")

# Convert to PCM16 bytes
audio_data = recording.tobytes()

# Check amplitude
max_amplitude = np.max(np.abs(recording))
print(f"Max amplitude: {max_amplitude:.4f}")
if max_amplitude < 1000:
    print("WARNING: Recording volume is very low. Speak closer to microphone.")

# Encode to base64
audio_base64 = base64.b64encode(audio_data).decode('utf-8')
print(f"Audio size: {len(audio_data)} bytes")
print(f"Base64 size: {len(audio_base64)} characters")

# Prepare request
session_id = f"live_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
request_data = {
    "audio": audio_base64,
    "sample_rate": SAMPLE_RATE,
    "session_id": session_id
}

print(f"\nSending to API: {API_URL}")
print(f"Session ID: {session_id}")

try:
    response = requests.post(API_URL, json=request_data, timeout=60)
    
    print(f"\nStatus Code: {response.status_code}")
    
    if response.status_code == 200:
        result = response.json()
        print(f"\nSuccess!")
        print(f"Audio size: {result.get('audio_size')} bytes")
        print(f"User transcript: {result.get('user_transcript')}")
        print(f"Agent transcript: {result.get('agent_transcript')}")
        
        # Save and play response audio if present
        if result.get('audio'):
            output_data = base64.b64decode(result['audio'])
            if len(output_data) > 0:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                output_file = f"response_{session_id}_{timestamp}.wav"
                
                # Create proper WAV header (44 bytes)
                data_size = len(output_data)
                header = b'RIFF'
                header += struct.pack('<I', 36 + data_size)  # file size - 8
                header += b'WAVE'
                header += b'fmt '
                header += struct.pack('<I', 16)  # fmt chunk size
                header += struct.pack('<H', 1)  # PCM
                header += struct.pack('<H', 1)  # mono
                header += struct.pack('<I', SAMPLE_RATE)
                header += struct.pack('<I', SAMPLE_RATE * 2)  # byte rate
                header += struct.pack('<H', 2)  # block align
                header += struct.pack('<H', 16)  # bits per sample
                header += b'data'
                header += struct.pack('<I', data_size)
                
                # Save as WAV file (with header)
                full_wav = header + output_data
                with open(output_file, 'wb') as f:
                    f.write(full_wav)
                print(f"Response audio saved to: {output_file}")
                
                # Play the PCM audio directly (without WAV header)
                print("Playing agent response...")
                try:
                    # Convert bytes to numpy array for playback
                    audio_array = np.frombuffer(output_data, dtype=np.int16)
                    sd.play(audio_array, SAMPLE_RATE)
                    sd.wait()
                    print("Playback complete!")
                except Exception as e:
                    print(f"Playback error: {e}")
    else:
        print(f"\nError: {response.status_code}")
        print(f"Detail: {response.text}")

except Exception as e:
    print(f"\nError: {e}")
    import traceback
    traceback.print_exc()

print("\n" + "=" * 60)