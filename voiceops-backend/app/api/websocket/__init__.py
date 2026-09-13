"""
WebSocket endpoints for VoiceOps.
"""
from app.api.websocket.voice_agent_router import router as voice_agent_router
from app.api.websocket.driver_ws import router as driver_ws_router

__all__ = ["voice_agent_router", "driver_ws_router"]