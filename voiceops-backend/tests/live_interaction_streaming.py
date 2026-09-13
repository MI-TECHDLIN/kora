"""
Live interaction with streaming audio playback for minimal latency.
Plays audio chunks as soon as they are received from the agent.
"""
import base64
import json
import sys
import os
import asyncio
import numpy as np
import sounddevice as sd
import requests
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SAMPLE_RATE = 24000
DURATION = 5
API_URL = "http://localhost:8000/v1/voice-agent-stream"

def record_audio(duration):
    """Record audio from microphone"""
    print(f"Recording for {duration} seconds...")
    print("Speak clearly into your microphone now.")
    
    recording = sd.rec(
        int(duration * SAMPLE_RATE),
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype='int16'
    )
    sd.wait()
    
    max_amplitude = np.max(np.abs(recording))
    print(f"Max amplitude: {max_amplitude:.4f}")
    if max_amplitude < 1000:
        print("WARNING: Recording volume is very low. Speak closer to microphone.")
    
    return recording.tobytes()

def play_audio_chunk(chunk_bytes):
    """Play a single audio chunk immediately"""
    try:
        if len(chunk_bytes) > 0:
            # Convert bytes to numpy array
            audio_array = np.frombuffer(chunk_bytes, dtype=np.int16)
            if len(audio_array) > 0:
                sd.play(audio_array, SAMPLE_RATE)
                return True
    except Exception as e:
        print(f"Error playing chunk: {e}")
    return False

async def stream_audio_response(user_audio_base64, session_id):
    """Stream audio response and play chunks as they arrive"""
    import websockets
    
    ws_url = f"ws://localhost:8000/ws/voice-agent-stream/{session_id}"
    
    try:
        async with websockets.connect(ws_url) as ws:
            # Send user audio
            await ws.send(json.dumps({
                "type": "audio_input",
                "audio": user_audio_base64
            }))
            
            print("Waiting for agent response...")
            
            # Stream and play audio chunks
            audio_buffer = np.array([], dtype=np.int16)
            chunks_received = 0
            
            while True:
                try:
                    message = await asyncio.wait_for(ws.recv(), timeout=5.0)
                    data = json.loads(message)
                    msg_type = data.get("type")
                    
                    if msg_type == "audio_chunk":
                        chunk_b64 = data.get("audio")
                        if chunk_b64:
                            chunk_bytes = base64.b64decode(chunk_b64)
                            audio_array = np.frombuffer(chunk_bytes, dtype=np.int16)
                            audio_buffer = np.concatenate([audio_buffer, audio_array])
                            chunks_received += 1
                            
                            # Play chunk immediately for minimal latency
                            sd.play(audio_array, SAMPLE_RATE)
                            sd.wait()  # Wait for this chunk to finish
                            
                            if chunks_received % 10 == 0:
                                print(f"Received {chunks_received} chunks")
                    
                    elif msg_type == "text":
                        text = data.get("text", "")
                        print(f"Agent: {text}")
                    
                    elif msg_type == "user_transcript":
                        text = data.get("text", "")
                        print(f"You said: {text}")
                    
                    elif msg_type == "done":
                        print("Response complete")
                        break
                    
                    elif msg_type == "error":
                        print(f"Error: {data.get('message')}")
                        break
                        
                except asyncio.TimeoutError:
                    print("Timeout waiting for response")
                    break
            
            return True
            
    except Exception as e:
        print(f"Streaming error: {e}")
        return False

def main():
    """Run streaming voice interaction"""
    print("=" * 60)
    print("STREAMING LIVE INTERACTION WITH MINIMAL LATENCY")
    print("=" * 60)
    print("\nAudio will play as soon as chunks are received!")
    print("\nAvailable commands to try:")
    print("  - 'What's my next delivery?'")
    print("  - 'Get me the fastest route'")
    print("  - 'Call the customer'")
    print("  - 'How am I doing?'")
    print("  - 'Mark as delivered'")
    print("=" * 60)
    
    # Generate unique session ID
    session_id = f"live_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    print(f"\nSession ID: {session_id}")
    print(f"WebSocket URL: ws://localhost:8000/ws/voice-agent-stream/{session_id}\n")
    
    # Record user input
    try:
        user_audio = record_audio(DURATION)
        print("Recording complete.")
    except KeyboardInterrupt:
        print("\nRecording interrupted by user.")
        return
    
    # Stream and play response
    print(f"\nStreaming audio response...")
    user_audio_base64 = base64.b64encode(user_audio).decode('utf-8')
    
    try:
        success = asyncio.run(stream_audio_response(user_audio_base64, session_id))
        if success:
            print("\nStreaming interaction complete!")
        else:
            print("\nStreaming interaction failed.")
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
