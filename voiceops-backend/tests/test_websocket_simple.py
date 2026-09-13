"""
Simple WebSocket test client for debugging.
"""
import asyncio
import websockets
import json

async def test_websocket():
    """Test basic WebSocket connection"""
    uri = "ws://localhost:8000/ws/voice-agent/test-driver-001"
    
    try:
        print(f"Connecting to {uri}...")
        async with websockets.connect(uri) as websocket:
            print("Connected successfully!")
            
            # Wait for initial messages
            try:
                message = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                print(f"Received: {message}")
                
                data = json.loads(message)
                print(f"Parsed: {data}")
                
            except asyncio.TimeoutError:
                print("Timeout waiting for initial message")
                
            # Send a ping
            print("Sending ping...")
            await websocket.send(json.dumps({"type": "ping"}))
            
            # Wait for pong
            try:
                response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                print(f"Received: {response}")
                data = json.loads(response)
                print(f"Parsed: {data}")
            except asyncio.TimeoutError:
                print("Timeout waiting for pong response")
            
            # Keep connection open for a bit
            print("Keeping connection open for 3 seconds...")
            await asyncio.sleep(3)
                
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_websocket())