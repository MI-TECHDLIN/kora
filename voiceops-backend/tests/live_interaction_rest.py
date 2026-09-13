"""
Live interaction with AssemblyAI Voice Agent using REST API.
This is the working version that uses the existing REST endpoint.
"""
import sys
import os
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import sounddevice as sd
import numpy as np
import requests
import json
import base64
import struct
import time
from datetime import datetime

# Configuration
SAMPLE_RATE = 24000  # AssemblyAI requires 24 kHz
DURATION = 5  # seconds to record
API_URL = "http://localhost:8000/v1/voice-agent"

def play_audio(audio_data, sample_rate=SAMPLE_RATE):
    """Play audio data using sounddevice"""
    try:
        if len(audio_data) == 0:
            print("No audio data to play")
            return False
            
        audio_array = np.frombuffer(audio_data, dtype=np.int16)
        
        # Normalize audio to prevent clipping
        if len(audio_array) > 0:
            max_val = np.max(np.abs(audio_array))
            if max_val > 0:
                audio_array = (audio_array / max_val * 0.8).astype(np.int16)
        
        print(f"Playing {len(audio_array)} samples ({len(audio_array)/sample_rate:.1f}s)...")
        sd.play(audio_array, sample_rate)
        sd.wait()
        print("Playback complete!")
        return True
    except Exception as e:
        print(f"Playback error: {e}")
        import traceback
        traceback.print_exc()
        return False

def save_wav(audio_data, filename, sample_rate=SAMPLE_RATE):
    """Save audio data as WAV file"""
    if len(audio_data) == 0:
        print("No audio data to save")
        return False
        
    data_size = len(audio_data)
    header = b'RIFF'
    header += struct.pack('<I', 36 + data_size)  # file size - 8
    header += b'WAVE'
    header += b'fmt '
    header += struct.pack('<I', 16)  # fmt chunk size
    header += struct.pack('<H', 1)  # PCM
    header += struct.pack('<H', 1)  # mono
    header += struct.pack('<I', sample_rate)
    header += struct.pack('<I', sample_rate * 2)  # byte rate
    header += struct.pack('<H', 2)  # block align
    header += struct.pack('<H', 16)  # bits per sample
    header += b'data'
    header += struct.pack('<I', data_size)
    
    full_wav = header + audio_data
    with open(filename, 'wb') as f:
        f.write(full_wav)
    return True

def send_voice_request(audio_base64, session_id):
    """Send audio request to API"""
    request_data = {
        "audio": audio_base64,
        "sample_rate": SAMPLE_RATE,
        "session_id": session_id
    }
    
    response = requests.post(API_URL, json=request_data, timeout=60)
    return response

def record_audio(duration):
    """Record audio from microphone"""
    print(f"Recording for {duration} seconds...")
    print("Speak clearly into your microphone now.")
    
    recording = sd.rec(int(duration * SAMPLE_RATE), 
                       samplerate=SAMPLE_RATE, 
                       channels=1,
                       dtype='int16')
    sd.wait()
    
    # Check amplitude
    max_amplitude = np.max(np.abs(recording))
    print(f"Max amplitude: {max_amplitude:.4f}")
    if max_amplitude < 1000:
        print("WARNING: Recording volume is very low. Speak closer to microphone.")
    
    return recording.tobytes()

def main():
    """Run single voice interaction"""
    print("=" * 60)
    print("LIVE INTERACTION WITH ASSEMBLYAI VOICE AGENT")
    print("=" * 60)
    print("\nNOTE: Each request creates a new session.")
    print("The agent will greet you and then respond to your command.")
    print("\nAvailable commands to try:")
    print("  - 'What's my next delivery?'")
    print("  - 'Get me the fastest route'")
    print("  - 'Call the customer'")
    print("  - 'How am I doing?'")
    print("  - 'Mark as delivered'")
    print("=" * 60)
    
    # Generate unique session ID for this interaction
    session_id = f"live_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    print(f"\nSession ID: {session_id}")
    print(f"API URL: {API_URL}\n")
    
    # Record user input
    try:
        user_audio = record_audio(DURATION)
        print("Recording complete.")
    except KeyboardInterrupt:
        print("\nRecording interrupted by user.")
        return
    
    # Send to API
    print(f"\nSending request to agent...")
    user_audio_base64 = base64.b64encode(user_audio).decode('utf-8')
    
    try:
        response = send_voice_request(user_audio_base64, session_id)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            
            # Display transcripts
            user_transcript = result.get('user_transcript', '')
            agent_transcript = result.get('agent_transcript', '')
            
            if user_transcript:
                print(f"\nYou said: {user_transcript}")
            if agent_transcript:
                print(f"Agent: {agent_transcript}")
            
            # Handle audio response
            if result.get('audio'):
                response_audio = base64.b64decode(result['audio'])
                if len(response_audio) > 0:
                    print(f"\nAudio response received: {len(response_audio)} bytes")
                    
                    # Save response audio
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    response_file = f"response_{session_id}_{timestamp}.wav"
                    if save_wav(response_audio, response_file):
                        print(f"Response saved to: {response_file}")
                    
                    # Play response
                    print("\nPlaying agent response...")
                    if play_audio(response_audio):
                        print("Response playback complete!")
                    else:
                        print("Could not play response audio")
                else:
                    print("\nNo audio data in response")
            else:
                print("\nNo audio in response (text only)")
                
        else:
            print(f"\nError: {response.status_code}")
            print(f"Detail: {response.text}")
            
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
    
    print("\n" + "=" * 60)
    print("Interaction complete!")
    print("=" * 60)

if __name__ == "__main__":
    main()