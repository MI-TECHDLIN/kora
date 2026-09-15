"""
WebSocket endpoints for VoiceOps.
"""
from app.api.websocket.voice import router as voice_router
from app.api.websocket.driver_ws import router as driver_ws_router

__all__ = ["voice_router", "driver_ws_router"]
