from fastapi import APIRouter, HTTPException, status, Depends, BackgroundTasks
from pydantic import BaseModel
from datetime import datetime, timezone
from app.dependencies import get_current_driver
from app.db.queries import (
    create_shift,
    update_shift_status,
    get_shift_stats,
    get_shift_voice_sessions,
    get_intelligence_report_by_shift
)
from app.integrations.n8n_client import trigger_post_shift_report_background


router = APIRouter()


class ShiftStartResponse(BaseModel):
    shift_id: str
    status: str
    message: str


class ShiftEndResponse(BaseModel):
    shift_id: str
    status: str
    message: str


@router.post("/start", response_model=ShiftStartResponse)
async def start_shift(
    current_user: dict = Depends(get_current_driver)
):
    """Start a new shift."""
    try:
        shift = await create_shift(current_user["id"])
        return ShiftStartResponse(
            shift_id=shift["id"],
            status=shift["status"],
            message="Shift started successfully"
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to start shift: {str(e)}"
        )


@router.post("/{shift_id}/end", response_model=ShiftEndResponse)
async def end_shift(
    shift_id: str,
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_driver)
):
    """End shift and trigger post-shift intelligence pipeline via n8n."""
    try:
        # Mark shift as completed in Supabase
        await update_shift_status(shift_id, "completed")

        # Pull real stats to build the intelligence payload
        stats = await get_shift_stats(shift_id)
        sessions = await get_shift_voice_sessions(shift_id)

        # Trigger post-shift intelligence — fire-and-forget, zero API latency impact
        trigger_post_shift_report_background(
            shift_id=shift_id,
            driver_id=current_user["id"],
            driver_name=current_user.get("full_name") or current_user.get("email", "Driver"),
            total_deliveries=stats.get("total", 0),
            delivered_count=stats.get("delivered", 0),
            failed_count=stats.get("failed", 0),
            shift_duration_min=0,        # TODO: compute from shift.started_at → now
            dispatcher_alerts=0,         # TODO: query dispatcher_alerts table by shift_id
            voice_sessions=len(sessions),
            shift_date=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            ended_at=datetime.now(timezone.utc).isoformat(),
        )

        return ShiftEndResponse(
            shift_id=shift_id,
            status="completed",
            message="Shift ended. Intelligence report is being generated."
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to end shift: {str(e)}"
        )


@router.get("/{shift_id}/report")
async def get_shift_report(
    shift_id: str,
    current_user: dict = Depends(get_current_driver)
):
    """Get intelligence report for shift."""
    report = await get_intelligence_report_by_shift(shift_id)

    if not report:
        return {"status": "processing", "message": "Report is being generated"}

    return report


@router.get("/{shift_id}/stats")
async def get_shift_statistics(
    shift_id: str,
    current_user: dict = Depends(get_current_driver)
):
    """Get shift statistics."""
    stats = await get_shift_stats(shift_id)
    return stats
