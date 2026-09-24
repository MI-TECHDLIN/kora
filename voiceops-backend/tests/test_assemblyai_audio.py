"""
Test AssemblyAI audio streaming with simple session configuration.
"""
import asyncio
import json
import os
import sys
import requests
import websockets
import base64
import numpy as np
import pytest

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.config import settings

pytestmark = [
    pytest.mark.live,
    pytest.mark.credentials("assemblyai_api_key"),
    pytest.mark.asyncio,
]

SAMPLE_RATE = 24000
CHUNK_SIZE = 2400  # 50ms at 24kHz, 16-bit mono

async def test_assemblyai_audio_streaming():
    """Test AssemblyAI audio streaming with a simple voice request"""
    print("=" * 60)
    print("TEST: AssemblyAI Audio Streaming")
    print("=" * 60)
    
    # Generate temporary token
    token_url = f"https://agents.assemblyai.com/v1/token?expires_in_seconds=300"
    response = requests.get(token_url, headers={"Authorization": f"Bearer {settings.assemblyai_api_key}"})
    
    if response.status_code != 200:
        print(f"Failed to generate token: {response.status_code}")
        return
    
    token_data = response.json()
    temp_token = token_data.get("token")
    print(f"Token generated: {temp_token[:50]}...")
    
    ws_url = f"wss://agents.assemblyai.com/v1/ws?token={temp_token}"
    print(f"Connecting to: {ws_url}")
    
    try:
        async with websockets.connect(ws_url) as ws:
            print("WebSocket connected!")
            
            # Send session configuration
            session_config = {
                "type": "session.update",
                "session": {
                    "system_prompt": "You are a test assistant. Respond briefly with audio.",
                    "greeting": "Hello! I'm ready to help.",
                    "input": {"format": {"encoding": "audio/pcm"}},
                    "output": {"format": {"encoding": "audio/pcm"}, "voice": "anna"}
                }
            }
            
            print("Sending session config...")
            await ws.send(json.dumps(session_config))
            
            # Wait for session.updated
            response = await asyncio.wait_for(ws.recv(), timeout=10.0)
            data = json.loads(response)
            print(f"First response: {data.get('type')}")
            
            if data.get("type") == "session.updated":
                print("Session updated")
                # Wait for session.ready
                response = await asyncio.wait_for(ws.recv(), timeout=10.0)
                data = json.loads(response)
                print(f"Second response: {data.get('type')}")
                
                if data.get("type") == "session.ready":
                    print("Session ready!")
                    
                    # Send some silence audio to trigger greeting
                    silence_chunk = np.zeros(CHUNK_SIZE, dtype=np.int16).tobytes()
                    silence_b64 = base64.b64encode(silence_chunk).decode('utf-8')
                    
                    print("Sending silence chunk to trigger greeting...")
                    await ws.send(json.dumps({"type": "input.audio", "audio": silence_b64}))
                    
                    # Listen for messages
                    print("Listening for response...")
                    message_count = 0
                    audio_chunks = []
                    agent_texts = []
                    
                    while message_count < 100:  # Listen for up to 100 messages
                        try:
                            response = await asyncio.wait_for(ws.recv(), timeout=5.0)
                            data = json.loads(response)
                            msg_type = data.get("type")
                            message_count += 1
                            
                            print(f"Message {message_count}: {msg_type}")
                            
                            if msg_type == "reply.audio":
                                audio_data = data.get("data")  # AssemblyAI uses "data" field
                                if audio_data:
                                    audio_chunks.append(base64.b64decode(audio_data))
                                    print(f"  Audio chunk: {len(audio_data)} chars")
                                else:
                                    print(f"  Audio chunk: NO AUDIO DATA in message")
                                    print(f"  Full message: {json.dumps(data)[:200]}")
                            
                            elif msg_type == "transcript.agent":
                                text = data.get("text", "")
                                agent_texts.append(text)
                                print(f"  Agent text: {text}")
                            
                            elif msg_type == "transcript.agent.delta":
                                text = data.get("text", "")
                                if text:
                                    agent_texts.append(text)
                                    print(f"  Agent text delta: {text}")
                            
                            elif msg_type == "reply.done":
                                print("  Reply complete!")
                                break
                            
                            elif msg_type == "session.ended":
                                print("  Session ended")
                                break
                            
                            else:
                                print(f"  Other message type: {msg_type}")
                                if message_count <= 5:  # Show first few unknown messages
                                    print(f"  Data: {json.dumps(data)[:200]}")
                                
                        except asyncio.TimeoutError:
                            print("Timeout waiting for message")
                            break
                    
                    total_audio = b"".join(audio_chunks)
                    print(f"\nTotal audio received: {len(total_audio)} bytes")
                    print(f"Agent texts: {agent_texts}")
                    
                    if len(total_audio) > 0:
                        print("SUCCESS: Audio was received!")
                    else:
                        print("NO AUDIO: No audio chunks received")
                
                else:
                    print(f"Expected session.ready, got {data.get('type')}")
            else:
                print(f"Expected session.updated, got {data.get('type')}")
                
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_assemblyai_audio_streaming())
