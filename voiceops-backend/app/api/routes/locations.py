"""
Locations & GPS Tracking API Routes
Handles live GPS pings, driver movement tracking, geofence processing,
and historical trail queries.
"""
import logging
from typing import Optional, List
from fastapi import APIRouter, HTTPException, status, Depends, Query, BackgroundTasks
from pydantic import BaseModel, Field
from app.dependencies import get_current_driver
from app.services.location_service import location_service
from app.db.queries import (
    save_location_ping,
    update_driver_location,
    get_driver_by_id,
    get_recent_location_pings,
    is_valid_uuid,
)

logger = logging.getLogger(__name__)
router = APIRouter()


class LocationPingRequest(BaseModel):
    latitude: float = Field(..., ge=-90.0, le=90.0, description="Latitude between -90 and 90")
    longitude: float = Field(..., ge=-180.0, le=180.0, description="Longitude between -180 and 180")
    speed: float = Field(0.0, ge=0.0, le=300.0, description="Speed in km/h (0 to 300)")
    heading: float = Field(0.0, ge=0.0, le=360.0, description="Compass heading 0-360 degrees")
    accuracy: float = Field(0.0, ge=0.0, description="GPS accuracy in meters")
    shift_id: Optional[str] = Field(None, description="Active shift UUID")


@router.post("/locations/ping")
async def receive_location_ping(
    ping: LocationPingRequest,
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_driver),
):
    """
    Receive high-frequency GPS ping from mobile driver client.
    Updates driver's live position and runs geofencing/arrival intelligence.
    """
    driver_id = current_user.get("id")
    shift_id = ping.shift_id or current_user.get("current_shift_id", "")

    try:
        # 1. Store location ping
        await save_location_ping(
            driver_id=driver_id,
            shift_id=shift_id,
            lat=ping.latitude,
            lng=ping.longitude,
            speed=ping.speed,
            heading=ping.heading,
            accuracy=ping.accuracy,
        )

        # 2. Update driver's live coordinates
        await update_driver_location(
            driver_id=driver_id,
            lat=ping.latitude,
            lng=ping.longitude,
            heading=ping.heading,
            speed=ping.speed,
        )

        # 3. Trigger location intelligence (geofencing, arrival detection)
        events = await location_service.process_location_update(
            driver_id=driver_id,
            shift_id=shift_id,
            lat=ping.latitude,
            lng=ping.longitude,
            speed=ping.speed,
            heading=ping.heading,
            accuracy=ping.accuracy,
        )

        # 4. Run Proactive Risk Engine
        from app.services.risk_engine import risk_engine
        from app.services.proactive_alert_service import alert_service
        from app.services.notification_policy_service import notification_policy_service
        from app.services.eta_service import eta_service
        from app.db.queries import get_next_pending_delivery

        loc_data = {
            "latitude": ping.latitude,
            "longitude": ping.longitude,
            "speed": ping.speed,
            "heading": ping.heading,
        }

        detected_risks = await risk_engine.evaluate(driver_id, shift_id, loc_data)
        alerts_sent = []

        for risk in detected_risks:
            if await alert_service.should_alert(driver_id, risk.risk_type.value):
                # Extract route suggestion for ROUTE_DEVIATION alerts
                route_suggestion = None
                if risk.risk_type.value == "ROUTE_DEVIATION":
                    route_suggestion = {
                        "eta_minutes": risk.evidence.get("alternate_eta_minutes"),
                        "current_eta_minutes": risk.evidence.get("current_eta_minutes"),
                        "geometry": risk.evidence.get("geometry", ""),
                    }
                
                sent = await alert_service.emit_voice_alert(
                    driver_id=driver_id,
                    message=risk.recommended_action,
                    severity=risk.severity.value,
                    risk_type=risk.risk_type.value,
                    delivery_id=risk.delivery_id,
                    route_suggestion=route_suggestion,
                )
                if sent:
                    alerts_sent.append(risk.to_dict())

        # 5. Check Proactive Customer ETA Notification
        if is_valid_uuid(shift_id) and is_valid_uuid(driver_id):
            delivery = await get_next_pending_delivery(shift_id, driver_id)
            if delivery:
                dest_lat = delivery.get("dropoff_latitude") or delivery.get("latitude")
                dest_lng = delivery.get("dropoff_longitude") or delivery.get("longitude")
                if dest_lat is not None and dest_lng is not None:
                    # Use traffic-aware ETA with fallback to haversine
                    eta_result = await eta_service.compute_eta_minutes_traffic_aware(
                        (ping.latitude, ping.longitude),
                        (float(dest_lat), float(dest_lng)),
                        delivery_id=delivery["id"],
                        current_speed_kmh=ping.speed
                    )
                    eta = eta_result["eta_minutes"]
                    delivery_id = delivery["id"]
                    if await notification_policy_service.should_notify_customer(delivery_id, eta):
                        background_tasks.add_task(
                            notification_policy_service.send_eta_notification,
                            delivery_id,
                            eta
                        )

        return {
            "success": True,
            "driver_id": driver_id,
            "events_emitted": events,
            "risks_detected": [r.to_dict() for r in detected_risks],
            "alerts_dispatched": alerts_sent,
            "latitude": ping.latitude,
            "longitude": ping.longitude,
        }

    except Exception as e:
        logger.error(f"[Locations] Failed to process ping: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to record location ping: {str(e)}"
        )


@router.get("/drivers/{driver_id}/location")
async def get_driver_live_location(
    driver_id: str,
    current_user: dict = Depends(get_current_driver),
):
    """Get the current live location of a driver."""
    if not is_valid_uuid(driver_id):
        raise HTTPException(status_code=400, detail="Invalid driver_id UUID")

    driver = await get_driver_by_id(driver_id)
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    return {
        "driver_id": driver_id,
        "name": driver.get("name"),
        "status": driver.get("status", "off_duty"),
        "latitude": driver.get("current_latitude"),
        "longitude": driver.get("current_longitude"),
        "heading": driver.get("current_heading"),
        "speed": driver.get("current_speed"),
    }


@router.get("/drivers/{driver_id}/history")
async def get_location_history(
    driver_id: str,
    limit: int = Query(50, ge=1, le=500),
    current_user: dict = Depends(get_current_driver),
):
    """Get historical GPS breadcrumbs for a driver."""
    if not is_valid_uuid(driver_id):
        raise HTTPException(status_code=400, detail="Invalid driver_id UUID")

    pings = await get_recent_location_pings(driver_id, limit=limit)
    return {
        "driver_id": driver_id,
        "count": len(pings),
        "pings": pings,
    }
