"""
Simple WebSocket test to verify AssemblyAI integration with FastAPI.
"""
import asyncio
import websockets
import json
import os
from dotenv import load_dotenv

load_dotenv()

ASSEMBLYAI_API_KEY = os.getenv("ASSEMBLYAI_API_KEY")


async def test_websocket_connection():
    """Test WebSocket connection to our FastAPI server."""
    print("Testing WebSocket connection to FastAPI server...")
    
    try:
        uri = "ws://localhost:8000/ws/voice/test-shift-123"
        
        async with websockets.connect(uri) as websocket:
            print("Connected to FastAPI WebSocket")
            
            # Listen for messages
            print("Listening for messages...")
            
            # Wait for a few messages
            for i in range(5):
                try:
                    message = await asyncio.wait_for(websocket.recv(), timeout=10.0)
                    data = json.loads(message)
                    print(f"Received: {data}")
                    
                    if data.get("type") == "session.ready":
                        print("Session ready!")
                        break
                        
                except asyncio.TimeoutError:
                    print("Timeout waiting for messages")
                    break
            
            print("WebSocket test completed")
            return True
            
    except Exception as e:
        print(f"WebSocket test failed: {e}")
        return False


async def main():
    print("=" * 50)
    print("FastAPI WebSocket Test")
    print("=" * 50)
    
    await test_websocket_connection()
    
    print("\n" + "=" * 50)
    print("Test completed")
    print("=" * 50)


if __name__ == "__main__":
    asyncio.run(main())
