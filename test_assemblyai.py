"""
Simple test script to verify AssemblyAI Voice Agent API connection.
Run this to test your API key before integrating with FastAPI.
"""
import asyncio
import websockets
import json
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

ASSEMBLYAI_API_KEY = os.getenv("ASSEMBLYAI_API_KEY")

if not ASSEMBLYAI_API_KEY or ASSEMBLYAI_API_KEY == "your_assemblyai_api_key_here":
    print("Please set ASSEMBLYAI_API_KEY in your .env file")
    print("Get your free API key at: https://www.assemblyai.com/")
    exit(1)


async def test_assemblyai_connection():
    """Test basic AssemblyAI Voice Agent API connection."""
    print("Connecting to AssemblyAI Voice Agent API...")
    
    try:
        # For websockets 15.x, use additional_headers parameter
        headers = {"Authorization": f"Bearer {ASSEMBLYAI_API_KEY}"}
        
        async with websockets.connect(
            "wss://agents.assemblyai.com/v1/ws",
            additional_headers=headers
        ) as websocket:
            print("Connected to AssemblyAI")
            
            # Send session configuration
            session_config = {
                "type": "session.update",
                "session": {
                    "system_prompt": "You are a test assistant. Keep replies short.",
                    "greeting": "Hello! This is a test."
                }
            }
            
            await websocket.send(json.dumps(session_config))
            print("Sent session configuration")
            
            # Listen for responses
            print("Listening for responses...")
            
            # Wait for session.ready or session.updated
            response = await websocket.recv()
            data = json.loads(response)
            
            if data.get("type") in ["session.ready", "session.updated"]:
                session_id = data.get("config", {}).get("id", "unknown")
                print(f"Session ready: {session_id}")
                print("AssemblyAI connection test PASSED")
                return True
            else:
                print(f"Unexpected response: {data}")
                return False
                
    except Exception as e:
        print(f"Connection failed: {e}")
        print("Check your API key and internet connection")
        return False


async def main():
    """Run all tests."""
    print("=" * 50)
    print("AssemblyAI Voice Agent API Test Suite")
    print("=" * 50)
    
    # Test 1: Basic connection
    connection_ok = await test_assemblyai_connection()
    
    print("\n" + "=" * 50)
    if connection_ok:
        print("All tests PASSED")
    else:
        print("Tests FAILED")
    print("=" * 50)


if __name__ == "__main__":
    asyncio.run(main())
