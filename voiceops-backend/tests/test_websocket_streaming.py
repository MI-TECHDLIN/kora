"""
Test WebSocket streaming with minimal latency audio playback.
Audio chunks are played as soon as they are received.
"""
import asyncio
import json
import base64
import sys
import os
import sounddevice as sd
import numpy as np
import websockets

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SAMPLE_RATE = 24000
CHUNK_SIZE = 2400  # 50ms at 24kHz

async def test_websocket_streaming():
    """Test WebSocket streaming with immediate audio playback"""
    driver_id = "test_streaming"
    ws_url = f"ws://localhost:8000/ws/voice-agent/{driver_id}"
    
    print("=" * 60)
    print("WEBSOCKET STREAMING TEST - MINIMAL LATENCY")
    print("=" * 60)
    print(f"Connecting to: {ws_url}")
    
    try:
        async with websockets.connect(ws_url) as ws:
            print("Connected successfully!")
            
            # Wait for session ready
            response = await ws.recv()
            data = json.loads(response)
            print(f"Received: {data.get('type')}")
            
            if data.get('type') == 'session_ready':
                print(f"Session ID: {data.get('session_id')}")
                
                # Wait for AssemblyAI ready
                response = await ws.recv()
                data = json.loads(response)
                print(f"Received: {data.get('type')}")
                
                if data.get('type') == 'assemblyai_ready':
                    print("AssemblyAI ready - sending ping")
                    
                    # Send ping
                    await ws.send(json.dumps({"type": "ping"}))
                    
                    # Wait for pong
                    response = await ws.recv()
                    data = json.loads(response)
                    print(f"Received: {data.get('type')}")
                    
                    # Send audio message to trigger agent response
                    print("\nSending audio message to agent...")
                    
                    # Generate a short silence audio chunk to trigger the greeting
                    silence_chunk = np.zeros(CHUNK_SIZE, dtype=np.int16).tobytes()
                    silence_b64 = base64.b64encode(silence_chunk).decode('utf-8')
                    
                    await ws.send(json.dumps({
                        "type": "audio_chunk",
                        "audio": silence_b64
                    }))
                    
                    # Listen for audio chunks and play immediately
                    print("Listening for agent response (playing chunks as they arrive)...")
                    chunks_received = 0
                    total_audio_bytes = 0
                    
                    while chunks_received < 100:  # Listen for up to 100 chunks
                        try:
                            response = await asyncio.wait_for(ws.recv(), timeout=10.0)
                            data = json.loads(response)
                            msg_type = data.get('type')
                            
                            if msg_type == 'agent_audio':
                                audio_b64 = data.get('audio')
                                if audio_b64:
                                    audio_bytes = base64.b64decode(audio_b64)
                                    audio_array = np.frombuffer(audio_bytes, dtype=np.int16)
                                    
                                    print(f"Playing chunk {chunks_received + 1}: {len(audio_array)} samples")
                                    
                                    # Play immediately for minimal latency
                                    try:
                                        sd.play(audio_array, SAMPLE_RATE)
                                        sd.wait()  # Wait for this chunk to finish
                                        print(f"  OK: Chunk played successfully")
                                    except Exception as play_error:
                                        print(f"  ERROR: Playback error: {play_error}")
                                    
                                    chunks_received += 1
                                    total_audio_bytes += len(audio_bytes)
                                    
                                    if chunks_received % 10 == 0:
                                        print(f"Received {chunks_received} chunks, {total_audio_bytes // 1024}KB total")
                                else:
                                    print("ERROR: Empty audio data received")
                            
                            elif msg_type == 'agent_text':
                                text = data.get('text', '')
                                print(f"Agent text: {text}")
                            
                            elif msg_type == 'error':
                                print(f"Error: {data.get('message')}")
                                break
                            
                            elif msg_type == 'pong':
                                print("Pong received")
                            
                            else:
                                print(f"Other message: {msg_type}")
                                
                        except asyncio.TimeoutError:
                            print("Timeout waiting for response")
                            break
                    
                    print(f"\nStreaming complete! Received {chunks_received} chunks, {total_audio_bytes // 1024}KB total")
                    
                else:
                    print(f"Expected assemblyai_ready, got {data.get('type')}")
            else:
                print(f"Expected session_ready, got {data.get('type')}")
                
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_websocket_streaming())
