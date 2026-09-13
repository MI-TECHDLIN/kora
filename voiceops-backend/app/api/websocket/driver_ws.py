"""
Real-time Driver WebSocket Channel
Provides bidirectional communication between backend and driver mobile app:
- Pushes proactive voice alerts
- Streams delivery updates
- Ingests low-latency GPS pings
- Dispatches emergency dispatcher messages
"""
import json
import logging
from typing import Dict, Any, Optional
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.services.location_service import location_service
from app.db.queries import save_location_ping, update_driver_location

logger = logging.getLogger(__name__)
router = APIRouter()


class DriverConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, driver_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[driver_id] = websocket
        logger.info(f"[WS] Driver {driver_id} connected. Active connections: {len(self.active_connections)}")

    async def disconnect(self, driver_id: str):
        self.active_connections.pop(driver_id, None)
        logger.info(f"[WS] Driver {driver_id} disconnected. Active connections: {len(self.active_connections)}")

    async def send_to_driver(self, driver_id: str, message: Dict[str, Any]) -> bool:
        ws = self.active_connections.get(driver_id)
        if ws:
            try:
                await ws.send_json(message)
                return True
            except Exception as e:
                logger.warning(f"[WS] Error sending message to driver {driver_id}: {e}")
                self.active_connections.pop(driver_id, None)
        return False

    async def broadcast(self, message: Dict[str, Any]):
        for driver_id, ws in list(self.active_connections.items()):
            try:
                await ws.send_json(message)
            except Exception:
                self.active_connections.pop(driver_id, None)


ws_manager = DriverConnectionManager()


@router.websocket("/ws/driver/{driver_id}")
async def driver_websocket_endpoint(websocket: WebSocket, driver_id: str):
    """
    Persistent WebSocket endpoint for driver mobile app.
    Message formats received:
      - {"type": "heartbeat"}
      - {"type": "location_ping", "payload": {latitude, longitude, speed, heading, shift_id}}
      - {"type": "ack", "alert_id": "..."}
    """
    await ws_manager.connect(driver_id, websocket)
    try:
        while True:
            raw_data = await websocket.receive_text()
            try:
                msg = json.loads(raw_data)
            except Exception:
                continue

            msg_type = msg.get("type", "")

            if msg_type == "heartbeat":
                await websocket.send_json({"type": "heartbeat_ack"})

            elif msg_type == "location_ping":
                payload = msg.get("payload", {})
                lat = payload.get("latitude")
                lng = payload.get("longitude")
                speed = payload.get("speed", 0.0)
                heading = payload.get("heading", 0.0)
                shift_id = payload.get("shift_id", "")

                if lat is not None and lng is not None:
                    # Async update
                    await save_location_ping(driver_id, shift_id, float(lat), float(lng), float(speed), float(heading))
                    await update_driver_location(driver_id, float(lat), float(lng), float(heading), float(speed))

                    events = await location_service.process_location_update(
                        driver_id, shift_id, float(lat), float(lng), float(speed), float(heading)
                    )
                    if events:
                        await websocket.send_json({
                            "type": "LOCATION_EVENTS",
                            "events": events
                        })

    except WebSocketDisconnect:
        await ws_manager.disconnect(driver_id)
    except Exception as e:
        logger.error(f"[WS] Exception in driver {driver_id} loop: {e}")
        await ws_manager.disconnect(driver_id)
