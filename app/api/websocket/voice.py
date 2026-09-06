from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, status
from typing import Optional
import json
import asyncio
import base64
from app.config import settings
from app.agents.tool_registry import build_session_config
from app.agents.orchestrator import ToolOrchestrator
from app.db.queries import create_voice_session, update_voice_session, log_tool_execution


router = APIRouter()


class VoiceWebSocketHandler:
    def __init__(self, websocket: WebSocket, shift_id: str, driver_id: str):
        self.websocket = websocket
        self.shift_id = shift_id
        self.driver_id = driver_id
        self.aai_websocket: Optional[WebSocket] = None
        self.session_id: Optional[str] = None
        self.tool_orchestrator = ToolOrchestrator()
        self.pending_tool_results = []
        self.reply_done_received = False
        
    async def connect(self):
        """Accept WebSocket connection and connect to AssemblyAI."""
        await self.websocket.accept()
        
        # Skip DB operations for testing
        self.session_id = "test-session-123"
        
        # Connect to AssemblyAI Voice Agent API
        try:
            import websockets
            headers = {"Authorization": f"Bearer {settings.assemblyai_api_key}"}
            self.aai_websocket = await websockets.connect(
                "wss://agents.assemblyai.com/v1/ws",
                additional_headers=headers
            )
            
            # Send session configuration with inline config (not stored agent)
            session_config = await build_session_config(
                driver_id=self.driver_id,
                shift_id=self.shift_id
            )
            
            await self.aai_websocket.send(json.dumps(session_config))
            
            # Start parallel tasks
            await asyncio.gather(
                self._relay_app_to_aai(),
                self._relay_aai_to_app()
            )
            
        except Exception as e:
            await self.websocket.send_json({
                "type": "error",
                "message": f"Failed to connect to AssemblyAI: {str(e)}"
            })
            await self.websocket.close()
    
    async def _relay_app_to_aai(self):
        """Forward audio from Flutter to AssemblyAI."""
        try:
            while True:
                # Receive raw audio bytes from Flutter
                data = await self.websocket.receive_bytes()
                
                # Base64-encode for AssemblyAI (24kHz PCM16)
                base64_audio = base64.b64encode(data).decode('utf-8')
                
                # Send to AssemblyAI as audio event
                audio_message = {
                    "type": "audio",
                    "audio": base64_audio
                }
                await self.aai_websocket.send(json.dumps(audio_message))
                
        except WebSocketDisconnect:
            print("Flutter WebSocket disconnected")
        except Exception as e:
            print(f"Error relaying app to AAI: {e}")
    
    async def _relay_aai_to_app(self):
        """Receive AssemblyAI messages and route to Flutter."""
        try:
            async for message in self.aai_websocket:
                data = json.loads(message)
                msg_type = data.get("type")
                
                if msg_type == "session.updated":
                    print(f"AssemblyAI session updated: {data.get('config', {}).get('id')}")
                    await self.websocket.send_json({
                        "type": "session.ready",
                        "session_id": data.get("config", {}).get("id")
                    })
                
                elif msg_type == "reply.started":
                    # Agent started responding
                    await self.websocket.send_json({
                        "type": "agent_started"
                    })
                
                elif msg_type == "reply.audio":
                    # TTS audio chunk - decode and send as bytes
                    audio_data = base64.b64decode(data.get("audio", ""))
                    await self.websocket.send_bytes(audio_data)
                
                elif msg_type == "reply.text":
                    # Transcript/response text
                    await self.websocket.send_json({
                        "type": "transcript",
                        "text": data.get("text", ""),
                        "role": "agent"
                    })
                
                elif msg_type == "user.transcript":
                    # User speech transcript
                    await self.websocket.send_json({
                        "type": "transcript",
                        "text": data.get("text", ""),
                        "role": "driver"
                    })
                
                elif msg_type == "tool.call":
                    # Tool call from agent - for now just acknowledge
                    await self.websocket.send_json({
                        "type": "tool_call",
                        "tool_name": data.get("name"),
                        "message": "Tool execution skipped for testing"
                    })
                
                elif msg_type == "reply.done":
                    # Agent finished speaking
                    await self.websocket.send_json({
                        "type": "reply_done"
                    })
                
                elif msg_type == "session.ended":
                    print("AssemblyAI session ended")
                    break
                
                elif msg_type == "error":
                    await self.websocket.send_json({
                        "type": "error",
                        "message": data.get("message", "Unknown error")
                    })
                
        except Exception as e:
            print(f"Error relaying AAI to app: {e}")
        finally:
            if self.aai_websocket:
                await self.aai_websocket.close()
    
    async def _handle_tool_call(self, tool_call: dict):
        """Execute tool call via orchestrator."""
        try:
            tool_name = tool_call.get("name")
            parameters = tool_call.get("parameters", {})
            tool_call_id = tool_call.get("tool_call_id")
            
            # Build context
            context = {
                "driver_id": self.driver_id,
                "shift_id": self.shift_id,
                "session_id": self.session_id
            }
            
            # Execute tool
            result = await self.tool_orchestrator.execute_single(
                tool_name, parameters, context
            )
            
            # Prepare tool result message
            tool_result = {
                "tool_call_id": tool_call_id,
                "output": result
            }
            
            # Log to DB
            await log_tool_execution(
                self.session_id,
                [tool_call],
                [result]
            )
            
            # If reply.done already received, send immediately
            # Otherwise, queue for after reply.done
            if self.reply_done_received:
                await self.websocket.send_json({
                    "type": "tool_result",
                    **tool_result
                })
            else:
                self.pending_tool_results.append(tool_result)
                
        except Exception as e:
            print(f"Tool execution error: {e}")
            error_result = {
                "tool_call_id": tool_call.get("tool_call_id"),
                "output": {"error": str(e)}
            }
            if self.reply_done_received:
                await self.websocket.send_json({
                    "type": "tool_result",
                    **error_result
                })
            else:
                self.pending_tool_results.append(error_result)


@router.websocket("/ws/voice/{shift_id}")
async def voice_websocket(
    websocket: WebSocket,
    shift_id: str
):
    """WebSocket endpoint for voice agent session."""
    # For testing, skip token validation
    # In production, validate with Supabase JWT
    await websocket.accept()
    
    try:
        # Create handler with mock driver_id for testing
        handler = VoiceWebSocketHandler(websocket, shift_id, "test-driver-123")
        await handler.connect()
        
    except WebSocketDisconnect:
        print("WebSocket disconnected")
    except Exception as e:
        print(f"WebSocket error: {e}")
        await websocket.close(code=status.WS_1011_INTERNAL_ERROR)
