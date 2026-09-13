"""
Simple test to verify AssemblyAI Voice Agent connection and authentication.
"""
import asyncio
import json
import os
import sys
import requests
import websockets

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Load settings
from app.config import settings

async def test_assemblyai_token():
    """Test generating temporary token"""
    print("=" * 60)
    print("TEST 1: Generate Temporary Token")
    print("=" * 60)
    
    token_url = f"https://agents.assemblyai.com/v1/token?expires_in_seconds=300"
    print(f"Token URL: {token_url}")
    
    response = requests.get(token_url, headers={"Authorization": f"Bearer {settings.assemblyai_api_key}"})
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text[:500]}")
    
    if response.status_code == 200:
        token_data = response.json()
        temp_token = token_data.get("token")
        print(f"Token generated: {temp_token[:50] if temp_token else 'None'}...")
        return temp_token
    else:
        print("Failed to generate token")
        return None

async def test_assemblyai_ws_with_token(token):
    """Test WebSocket connection with token"""
    print("\n" + "=" * 60)
    print("TEST 2: WebSocket Connection with Token")
    print("=" * 60)
    
    ws_url = f"wss://agents.assemblyai.com/v1/ws?token={token}"
    print(f"WebSocket URL: {ws_url}")
    
    try:
        async with websockets.connect(ws_url) as ws:
            print("WebSocket connected successfully!")
            
            # Send session configuration
            session_config = {
                "type": "session.update",
                "session": {
                    "system_prompt": "You are a test assistant. Say hello briefly.",
                    "greeting": "Hello from VoiceOps test!",
                    "input": {"format": {"encoding": "audio/pcm"}},
                    "output": {"format": {"encoding": "audio/pcm"}, "voice": "anna"}
                }
            }
            
            print(f"Sending session config...")
            await ws.send(json.dumps(session_config))
            
            # Wait for first response
            print("Waiting for response...")
            response = await asyncio.wait_for(ws.recv(), timeout=10.0)
            data = json.loads(response)
            print(f"First response type: {data.get('type')}")
            print(f"First response: {json.dumps(data, indent=2)[:500]}")
            
            if data.get("type") == "session.ready":
                print("Session ready successfully!")
                return True
            else:
                print(f"Unexpected response: {data.get('type')}")
                return False
                
    except Exception as e:
        print(f"WebSocket connection failed: {e}")
        return False

async def test_assemblyai_ws_with_headers():
    """Test WebSocket connection with headers"""
    print("\n" + "=" * 60)
    print("TEST 3: WebSocket Connection with Headers")
    print("=" * 60)
    
    ws_url = "wss://agents.assemblyai.com/v1/ws"
    print(f"WebSocket URL: {ws_url}")
    
    try:
        headers = {"Authorization": f"Bearer {settings.assemblyai_api_key}"}
        async with websockets.connect(ws_url, additional_headers=headers) as ws:
            print("WebSocket connected successfully!")
            
            # Send session configuration
            session_config = {
                "type": "session.update",
                "session": {
                    "system_prompt": "You are a test assistant. Say hello briefly.",
                    "greeting": "Hello from VoiceOps test!",
                    "input": {"format": {"encoding": "audio/pcm"}},
                    "output": {"format": {"encoding": "audio/pcm"}, "voice": "anna"}
                }
            }
            
            print(f"Sending session config...")
            await ws.send(json.dumps(session_config))
            
            # Wait for first response
            print("Waiting for response...")
            response = await asyncio.wait_for(ws.recv(), timeout=10.0)
            data = json.loads(response)
            print(f"First response type: {data.get('type')}")
            print(f"First response: {json.dumps(data, indent=2)[:500]}")
            
            if data.get("type") == "session.ready":
                print("Session ready successfully!")
                return True
            else:
                print(f"Unexpected response: {data.get('type')}")
                return False
                
    except Exception as e:
        print(f"WebSocket connection failed: {e}")
        return False

async def main():
    print(f"AssemblyAI API Key: {settings.assemblyai_api_key[:20]}...{settings.assemblyai_api_key[-10:]}")
    print(f"AssemblyAI Agent ID: {settings.assemblyai_agent_id}")
    
    # Test 1: Generate token
    token = await test_assemblyai_token()
    
    if token:
        # Test 2: Connect with token
        await test_assemblyai_ws_with_token(token)
    
    # Test 3: Connect with headers
    await test_assemblyai_ws_with_headers()
    
    print("\n" + "=" * 60)
    print("TESTS COMPLETE")
    print("=" * 60)

if __name__ == "__main__":
    asyncio.run(main())
