"""
WebSocket endpoint for real-time AssemblyAI Voice Agent interaction.
Provides persistent session management and bidirectional audio streaming.
"""
import json
import base64
import asyncio
import logging
from typing import Optional, Dict, Any
from fastapi import WebSocket, WebSocketDisconnect, status
from app.agents.context_builder import build_driver_context
from app.agents.tool_registry import execute_tool
from app.agents.orchestrator import ToolOrchestrator
from app.config import settings

logger = logging.getLogger(__name__)

# AssemblyAI WebSocket endpoint
ASSEMBLYAI_WS_URL = "wss://agents.assemblyai.com/v1/ws"

class VoiceAgentConnection:
    """Manages WebSocket connection between Flutter app and AssemblyAI"""
    
    def __init__(self, websocket: WebSocket, driver_id: str):
        self.websocket = websocket
        self.driver_id = driver_id
        self.session_id = f"ws_{driver_id}_{asyncio.get_event_loop().time()}"
        self.aai_ws: Optional[any] = None
        self.context: Dict[str, Any] = {}
        self.is_connected = False
        self.is_closing = False  # Flag to prevent duplicate close calls
        
    async def connect(self):
        """Establish connection with Flutter client and AssemblyAI"""
        try:
            # Accept WebSocket connection from Flutter
            await self.websocket.accept()
            logger.info(f"WebSocket connection accepted for driver {self.driver_id}")
            
            # Build driver context
            self.context = await build_driver_context(None, self.session_id)
            logger.info(f"Context built for driver {self.driver_id}")
            
            # Send session ready to client first (before AssemblyAI connection)
            await self._send_to_client({
                "type": "session_ready",
                "session_id": self.session_id,
                "driver_id": self.driver_id
            })
            
            # Connect to AssemblyAI using token-based authentication
            try:
                await self._connect_to_assemblyai()
                self.is_connected = True
            except Exception as aai_error:
                logger.error(f"AssemblyAI connection failed, running in text-only mode: {aai_error}")
                # Continue without AssemblyAI connection for testing
                self.is_connected = True
            
        except Exception as e:
            logger.error(f"Connection error: {e}")
            import traceback
            traceback.print_exc()
            await self.websocket.close(code=status.WS_1011_INTERNAL_ERROR)
    
    async def _connect_to_assemblyai(self):
        """Connect to AssemblyAI WebSocket using token-based authentication"""
        import websockets
        import requests
        
        # Generate temporary token for authentication
        token_url = f"https://agents.assemblyai.com/v1/token?expires_in_seconds=300"
        token_response = await asyncio.to_thread(
            lambda: requests.get(token_url, headers={"Authorization": f"Bearer {settings.assemblyai_api_key}"})
        )
        
        if token_response.status_code != 200:
            raise Exception(f"Failed to generate token: {token_response.status_code}")
        
        token_data = token_response.json()
        temp_token = token_data.get("token")
        
        if not temp_token:
            raise Exception("Failed to generate temporary token")
        
        ws_url_with_token = f"{ASSEMBLYAI_WS_URL}?token={temp_token}"
        
        try:
            self.aai_ws = await websockets.connect(
                ws_url_with_token,
                ping_interval=20,
                ping_timeout=20
            )
            logger.info(f"Connected to AssemblyAI for session {self.session_id}")
            
            # Configure AssemblyAI session
            await self._configure_assemblyai_session()
            
        except Exception as e:
            logger.error(f"AssemblyAI connection failed: {e}")
            raise
    
    async def _configure_assemblyai_session(self):
        """Configure AssemblyAI session with agent ID and tools"""
        try:
            from app.agents.agent_config import get_session_config
            
            # Get shift_id from context or use session_id as fallback
            shift_id = self.context.get("shift_id", self.session_id)
            
            config = get_session_config(
                driver_id=self.driver_id,
                shift_id=shift_id,
                agent_id=settings.assemblyai_agent_id
            )
            
            # Send session configuration directly
            await self.aai_ws.send(json.dumps(config))
            logger.info("AssemblyAI session configured")
            
        except Exception as e:
            logger.error(f"Session configuration failed: {e}")
    
    async def _send_to_client(self, message: Dict[str, Any]):
        """Send message to Flutter client"""
        try:
            await self.websocket.send_json(message)
        except Exception as e:
            logger.error(f"Failed to send to client: {e}")
    
    async def _send_to_assemblyai(self, message: Dict[str, Any]):
        """Send message to AssemblyAI"""
        try:
            await self.aai_ws.send(json.dumps(message))
        except Exception as e:
            logger.error(f"Failed to send to AssemblyAI: {e}")
    
    async def handle_client_message(self, message: Dict[str, Any]):
        """Handle incoming message from Flutter client"""
        msg_type = message.get("type")
        
        if msg_type == "audio_chunk":
            await self._handle_audio_chunk(message)
        elif msg_type == "text_input":
            await self._handle_text_input(message)
        elif msg_type == "ping":
            await self._handle_ping()
        else:
            logger.warning(f"Unknown message type: {msg_type}")
    
    async def _handle_audio_chunk(self, message: Dict[str, Any]):
        """Handle audio chunk from client"""
        try:
            audio_data = message.get("audio")
            if audio_data:
                # Forward audio to AssemblyAI
                await self._send_to_assemblyai({
                    "type": "input.audio",
                    "audio": audio_data
                })
        except Exception as e:
            logger.error(f"Audio chunk handling failed: {e}")
    
    async def _handle_text_input(self, message: Dict[str, Any]):
        """Handle text input from client"""
        try:
            text = message.get("text")
            if text:
                # Send text to AssemblyAI using the correct message type
                await self._send_to_assemblyai({
                    "type": "input.text",
                    "text": text
                })
        except Exception as e:
            logger.error(f"Text input handling failed: {e}")
    
    async def _handle_ping(self):
        """Handle ping from client"""
        await self._send_to_client({"type": "pong"})
    
    async def handle_assemblyai_message(self, message: str):
        """Handle incoming message from AssemblyAI"""
        try:
            data = json.loads(message)
            msg_type = data.get("type")
            
            if msg_type == "reply.audio":
                await self._handle_agent_audio(data)
            elif msg_type == "transcript.agent":
                await self._handle_agent_text(data)
            elif msg_type == "transcript.agent.delta":
                await self._handle_agent_text(data)
            elif msg_type == "transcript.user":
                await self._handle_user_transcript(data)
            elif msg_type == "transcript.user.delta":
                # Partial transcript, ignore for now
                pass
            elif msg_type == "tool.call":
                await self._handle_tool_call(data)
            elif msg_type == "tool.result":
                await self._handle_tool_result(data)
            elif msg_type == "session.ready":
                await self._handle_session_ready(data)
            elif msg_type == "session.updated":
                logger.info("AssemblyAI session updated")
            elif msg_type == "reply.started":
                logger.debug("Agent reply started")
            elif msg_type == "reply.done":
                logger.debug("Agent reply complete")
            elif msg_type == "session.ended":
                logger.info("AssemblyAI session ended")
            elif msg_type == "session.error":
                await self._handle_error(data)
            elif msg_type == "input.speech.started":
                logger.debug("User speech started")
            elif msg_type == "input.speech.stopped":
                logger.debug("User speech stopped")
            else:
                logger.debug(f"Unhandled AssemblyAI message type: {msg_type}")
                
        except json.JSONDecodeError as e:
            logger.error(f"JSON decode error: {e}")
        except Exception as e:
            logger.error(f"AssemblyAI message handling failed: {e}")
    
    async def _handle_agent_audio(self, data: Dict[str, Any]):
        """Handle agent audio response - forward immediately for minimal latency"""
        try:
            # AssemblyAI sends audio in the "data" field
            audio_data = data.get("data")
            if audio_data:
                # Forward immediately to client without buffering
                await self._send_to_client({
                    "type": "agent_audio",
                    "audio": audio_data
                })
                logger.debug(f"Forwarded audio chunk: {len(audio_data)} chars")
        except Exception as e:
            logger.error(f"Agent audio handling failed: {e}")
    
    async def _handle_agent_text(self, data: Dict[str, Any]):
        """Handle agent text response"""
        try:
            text = data.get("text", "")
            if text:
                await self._send_to_client({
                    "type": "agent_text",
                    "text": text
                })
        except Exception as e:
            logger.error(f"Agent text handling failed: {e}")
    
    async def _handle_user_transcript(self, data: Dict[str, Any]):
        """Handle user transcript from AssemblyAI"""
        try:
            text = data.get("text", "")
            if text:
                await self._send_to_client({
                    "type": "user_transcript",
                    "text": text
                })
        except Exception as e:
            logger.error(f"User transcript handling failed: {e}")
    
    async def _handle_tool_call(self, data: Dict[str, Any]):
        """Handle tool call from AssemblyAI"""
        try:
            tool_name = data.get("name")
            tool_args = data.get("arguments", {})
            call_id = data.get("call_id")
            
            logger.info(f"Tool call: {tool_name} with args: {tool_args}")
            
            # Execute tool
            result = await ToolOrchestrator.execute_single_tool(
                tool_name=tool_name,
                parameters=tool_args,
                context=self.context,
                call_id=call_id
            )
            
            # Send result back to AssemblyAI
            await self._send_to_assemblyai({
                "type": "tool.result",
                "call_id": call_id,
                "result": result
            })
            
        except Exception as e:
            logger.error(f"Tool call failed: {e}")
            # Send error result
            await self._send_to_assemblyai({
                "type": "tool.result",
                "call_id": data.get("call_id"),
                "result": {"success": False, "error": str(e)}
            })
    
    async def _handle_tool_result(self, data: Dict[str, Any]):
        """Handle tool result from AssemblyAI (if needed)"""
        # AssemblyAI sends tool results back to the agent
        pass
    
    async def _handle_session_ready(self, data: Dict[str, Any]):
        """Handle session ready from AssemblyAI"""
        logger.info("AssemblyAI session ready")
        await self._send_to_client({
            "type": "assemblyai_ready",
            "session_id": self.session_id
        })
    
    async def _handle_error(self, data: Dict[str, Any]):
        """Handle error from AssemblyAI"""
        error_msg = data.get("message", "Unknown error")
        logger.error(f"AssemblyAI error: {error_msg}")
        await self._send_to_client({
            "type": "error",
            "message": error_msg
        })
    
    async def start_message_loop(self):
        """Start the message processing loop"""
        try:
            # Only create AssemblyAI task if connection succeeded
            tasks = [asyncio.create_task(self._receive_from_client())]
            
            if self.aai_ws:
                tasks.append(asyncio.create_task(self._receive_from_assemblyai()))
            
            # Wait for either to complete
            done, pending = await asyncio.wait(
                tasks,
                return_when=asyncio.FIRST_COMPLETED
            )
            
            # Cancel pending tasks
            for task in pending:
                task.cancel()
                
        except Exception as e:
            logger.error(f"Message loop error: {e}")
        finally:
            await self.disconnect()
    
    async def _receive_from_client(self):
        """Receive messages from Flutter client"""
        try:
            while self.is_connected:
                message = await self.websocket.receive_json()
                await self.handle_client_message(message)
        except WebSocketDisconnect:
            logger.info(f"Client {self.driver_id} disconnected")
        except Exception as e:
            logger.error(f"Client receive error: {e}")
            logger.error(f"Error details: {str(e)}")
            # Don't set is_connected to False on general errors
            # Let the main loop handle disconnection
    
    async def _receive_from_assemblyai(self):
        """Receive messages from AssemblyAI"""
        try:
            while self.is_connected:
                message = await self.aai_ws.recv()
                await self.handle_assemblyai_message(message)
        except Exception as e:
            logger.error(f"AssemblyAI receive error: {e}")
    
    async def start_message_loop(self):
        """Start the message processing loop for bidirectional streaming"""
        try:
            # Only create AssemblyAI task if connection succeeded
            tasks = [asyncio.create_task(self._receive_from_client())]
            
            if self.aai_ws:
                tasks.append(asyncio.create_task(self._receive_from_assemblyai()))
            
            # Wait for either to complete
            done, pending = await asyncio.wait(
                tasks,
                return_when=asyncio.FIRST_COMPLETED
            )
            
            # Cancel pending tasks
            for task in pending:
                task.cancel()
                
        except Exception as e:
            logger.error(f"Message loop error: {e}")
        finally:
            await self.close()
    
    async def _receive_from_client(self):
        """Receive messages from Flutter client"""
        try:
            while self.is_connected:
                message = await self.websocket.receive_json()
                await self.handle_client_message(message)
        except WebSocketDisconnect:
            logger.info(f"Client {self.driver_id} disconnected")
        except Exception as e:
            logger.error(f"Client receive error: {e}")
    
    async def _receive_from_assemblyai(self):
        """Receive messages from AssemblyAI and forward immediately for minimal latency"""
        try:
            while self.is_connected:
                message = await self.aai_ws.recv()
                await self.handle_assemblyai_message(message)
        except Exception as e:
            logger.error(f"AssemblyAI receive error: {e}")
    
    async def close(self):
        """Clean up connections - idempotent method"""
        if self.is_closing:
            return  # Already closing, prevent duplicate calls
        
        self.is_closing = True
        self.is_connected = False
        
        try:
            if self.aai_ws:
                await self.aai_ws.close()
                self.aai_ws = None
        except Exception as e:
            logger.error(f"AssemblyAI disconnect error: {e}")
        
        try:
            if not self.websocket.client_state.DISCONNECTED:
                await self.websocket.close()
        except Exception as e:
            logger.error(f"Client disconnect error: {e}")
        
        logger.info(f"WebSocket session {self.session_id} ended")