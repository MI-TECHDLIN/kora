"""
WebSocket test client for voice agent endpoint.
Tests real-time voice interaction with AssemblyAI.
"""
import sys
import os
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import asyncio
import websockets
import json
import base64
import sounddevice as sd
import numpy as np
from datetime import datetime

# Configuration
WS_URL = "ws://localhost:8000/ws/voice-agent/test-driver-001"
SAMPLE_RATE = 24000
DURATION = 5  # seconds to record

class VoiceAgentTestClient:
    def __init__(self, driver_id="test-driver-001"):
        self.driver_id = driver_id
        self.ws_url = f"ws://localhost:8000/ws/voice-agent/{driver_id}"
        self.websocket = None
        self.is_connected = False
        self.recording_count = 0
        
    async def connect(self):
        """Connect to WebSocket server"""
        try:
            print(f"Connecting to {self.ws_url}...")
            self.websocket = await websockets.connect(self.ws_url)
            self.is_connected = True
            print("Connected successfully!")
            return True
        except Exception as e:
            print(f"Connection failed: {e}")
            return False
    
    async def disconnect(self):
        """Disconnect from WebSocket server"""
        if self.websocket:
            await self.websocket.close()
            self.is_connected = False
            print("Disconnected")
    
    async def send_audio_chunk(self, audio_data):
        """Send audio chunk to server"""
        if not self.is_connected:
            print("Not connected!")
            return False
        
        try:
            audio_base64 = base64.b64encode(audio_data).decode('utf-8')
            message = {
                "type": "audio_chunk",
                "audio": audio_base64
            }
            await self.websocket.send(json.dumps(message))
            return True
        except Exception as e:
            print(f"Failed to send audio: {e}")
            return False
    
    async def send_text(self, text):
        """Send text message to server"""
        if not self.is_connected:
            print("Not connected!")
            return False
        
        try:
            message = {
                "type": "text_input",
                "text": text
            }
            await self.websocket.send(json.dumps(message))
            return True
        except Exception as e:
            print(f"Failed to send text: {e}")
            return False
    
    async def listen_for_messages(self):
        """Listen for messages from server"""
        try:
            async for message in self.websocket:
                data = json.loads(message)
                await self.handle_message(data)
        except websockets.exceptions.ConnectionClosed:
            print("Connection closed by server")
        except Exception as e:
            print(f"Error receiving messages: {e}")
    
    async def handle_message(self, data):
        """Handle incoming message from server"""
        msg_type = data.get("type")
        
        if msg_type == "session_ready":
            print(f"Session ready: {data.get('session_id')}")
        elif msg_type == "assemblyai_ready":
            print("AssemblyAI connection ready!")
        elif msg_type == "agent_audio":
            print("Received agent audio")
            await self.play_agent_audio(data.get("audio"))
        elif msg_type == "agent_text":
            print(f"Agent: {data.get('text')}")
        elif msg_type == "error":
            print(f"Error: {data.get('message')}")
        elif msg_type == "pong":
            print("Pong received")
        else:
            print(f"Unknown message type: {msg_type}")
    
    async def play_agent_audio(self, audio_base64):
        """Play agent audio response"""
        try:
            audio_data = base64.b64decode(audio_base64)
            if len(audio_data) > 0:
                audio_array = np.frombuffer(audio_data, dtype=np.int16)
                
                # Normalize audio
                max_val = np.max(np.abs(audio_array))
                if max_val > 0:
                    audio_array = (audio_array / max_val * 0.8).astype(np.int16)
                
                print(f"Playing agent audio ({len(audio_array)/SAMPLE_RATE:.1f}s)...")
                sd.play(audio_array, SAMPLE_RATE)
                sd.wait()
                print("Playback complete")
        except Exception as e:
            print(f"Audio playback error: {e}")
    
    def record_audio(self, duration):
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
            print("WARNING: Recording volume is very low.")
        
        return recording.tobytes()
    
    async def interactive_session(self):
        """Run interactive voice session"""
        if not await self.connect():
            return
        
        try:
            # Start listening for messages in background
            listen_task = asyncio.create_task(self.listen_for_messages())
            
            # Wait for session to be ready
            print("Waiting for session to be ready...")
            await asyncio.sleep(2)
            
            # Interactive loop
            while self.is_connected:
                print("\n" + "=" * 60)
                print("Options:")
                print("1. Send voice command")
                print("2. Send text command")
                print("3. Send ping")
                print("4. Exit")
                print("=" * 60)
                
                choice = input("Choose option (1-4): ").strip()
                
                if choice == "1":
                    # Record and send audio
                    audio_data = self.record_audio(DURATION)
                    await self.send_audio_chunk(audio_data)
                    self.recording_count += 1
                    
                elif choice == "2":
                    # Send text
                    text = input("Enter your message: ").strip()
                    if text:
                        await self.send_text(text)
                        
                elif choice == "3":
                    # Send ping
                    await self.websocket.send(json.dumps({"type": "ping"}))
                    
                elif choice == "4":
                    # Exit
                    print("Exiting session...")
                    break
                    
                else:
                    print("Invalid choice")
                
                # Wait for response
                await asyncio.sleep(3)
            
            # Cancel listening task
            listen_task.cancel()
            
        except KeyboardInterrupt:
            print("\nInterrupted by user")
        except Exception as e:
            print(f"Session error: {e}")
        finally:
            await self.disconnect()

async def main():
    """Main test function"""
    print("=" * 60)
    print("VOICE AGENT WEBSOCKET TEST CLIENT")
    print("=" * 60)
    print("\nThis client connects to the WebSocket voice agent endpoint")
    print("and allows interactive voice/text communication.")
    print("\nMake sure the backend server is running on localhost:8000")
    print("=" * 60)
    
    client = VoiceAgentTestClient()
    await client.interactive_session()

if __name__ == "__main__":
    asyncio.run(main())