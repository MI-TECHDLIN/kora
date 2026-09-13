"""
WebSocket router for voice agent endpoint.
"""
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status
from app.api.websocket.voice_agent_connection import VoiceAgentConnection

router = APIRouter()

@router.websocket("/voice-agent/{driver_id}")
async def voice_agent_websocket(websocket: WebSocket, driver_id: str):
    """
    WebSocket endpoint for real-time voice agent interaction.
    
    Maintains persistent AssemblyAI session for continuous conversation.
    Supports bidirectional audio streaming and real-time tool execution.
    
    Message types from client:
    - audio_chunk: {"type": "audio_chunk", "audio": "base64_audio_data"}
    - text_input: {"type": "text_input", "text": "user_message"}
    - ping: {"type": "ping"}
    
    Message types to client:
    - session_ready: {"type": "session_ready", "session_id": "...", "driver_id": "..."}
    - assemblyai_ready: {"type": "assemblyai_ready", "session_id": "..."}
    - agent_audio: {"type": "agent_audio", "audio": "base64_audio_data"}
    - agent_text: {"type": "agent_text", "text": "agent_response"}
    - error: {"type": "error", "message": "error_message"}
    - pong: {"type": "pong"}
    """
    voice_agent = VoiceAgentConnection(websocket, driver_id)
    
    try:
        await voice_agent.connect()
        await voice_agent.start_message_loop()
    except WebSocketDisconnect:
        print(f"WebSocket disconnected for driver {driver_id}")
    except Exception as e:
        print(f"WebSocket error for driver {driver_id}: {e}")
    finally:
        # Only close if not already closed by the message loop
        await voice_agent.close()