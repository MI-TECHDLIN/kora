"""
Fleet Operations & Dispatcher API Routes
Provides fleet oversight, real-time tracking, incident management,
and operational metrics for dispatcher consoles.
"""
import logging
from typing import Optional
from fastapi import APIRouter, HTTPException, Query, Depends
from app.dependencies import get_current_driver
from app.agents.dispatcher_agent import dispatcher_agent
from app.db.queries import get_supabase

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/overview")
async def get_fleet_overview(current_user: dict = Depends(get_current_driver)):
    """Summary metrics of current fleet operations."""
    snapshot = await dispatcher_agent.get_fleet_snapshot()
    recommendations = await dispatcher_agent.evaluate_fleet_risk(snapshot)

    return {
        "overview": {
            "active_drivers": snapshot.get("active_drivers_count", 0),
            "active_shifts": snapshot.get("active_shifts_count", 0),
            "open_deliveries": snapshot.get("open_deliveries_count", 0),
            "unresolved_alerts": snapshot.get("unresolved_alerts_count", 0),
        },
        "recommendations": recommendations,
        "timestamp": snapshot.get("timestamp"),
    }


@router.get("/drivers")
async def get_fleet_drivers(current_user: dict = Depends(get_current_driver)):
    """List all active drivers with live telemetry and shift status."""
    try:
        supabase = get_supabase()
        res = (
            supabase.table("drivers")
            .select("id, name, phone, vehicle_type, status, current_latitude, current_longitude, current_heading, current_speed, current_shift_id")
            .execute()
        )
        return {"drivers": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch fleet drivers: {str(e)}")


@router.get("/incidents")
async def get_fleet_incidents(
    severity: Optional[str] = Query(None, description="Filter by severity: normal, urgent, critical"),
    resolved: bool = Query(False, description="Filter by resolution status"),
    current_user: dict = Depends(get_current_driver),
):
    """List operational alerts and driver incidents."""
    try:
        query = get_supabase().table("dispatcher_alerts").select("*").eq("resolved", resolved)
        if severity:
            query = query.eq("severity", severity)
        res = query.order("created_at", desc=True).limit(50).execute()
        return {"incidents": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch incidents: {str(e)}")


@router.get("/analytics")
async def get_fleet_analytics(
    current_user: dict = Depends(get_current_driver),
):
    """Aggregate fleet KPIs (completion rate, incident rate)."""
    try:
        supabase = get_supabase()
        deliv_res = supabase.table("deliveries").select("status").execute()
        deliveries = deliv_res.data or []

        total = len(deliveries)
        delivered = sum(1 for d in deliveries if d.get("status") == "delivered")
        failed = sum(1 for d in deliveries if d.get("status") == "failed")
        success_rate = round((delivered / total * 100), 1) if total > 0 else 100.0

        return {
            "total_deliveries": total,
            "delivered": delivered,
            "failed": failed,
            "success_rate_percentage": success_rate,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to calculate analytics: {str(e)}")
