from fastapi import APIRouter, HTTPException, status, Depends, BackgroundTasks
from pydantic import BaseModel
from datetime import datetime, timezone
from app.dependencies import get_current_driver
from app.db.queries import (
    create_shift,
    update_shift_status,
    get_shift_stats,
    get_shift_voice_sessions,
    get_intelligence_report_by_shift,
    get_shift_by_id
)
from app.integrations.n8n_client import trigger_post_shift_report_background
from app.intelligence.lemur_pipeline import run_shift_intelligence
from app.api.websocket.voice import stream_summary


router = APIRouter()


async def run_shift_intelligence_and_stream(shift_id: str, driver_id: str) -> dict:
    """Run the LeMUR pipeline, then stream its summary to the shift's open voice socket."""
    result = await run_shift_intelligence(shift_id, driver_id)
    await stream_summary(shift_id, result.get("analysis", {}).get("executive_summary", ""))
    return result


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
    """End shift and trigger AssemblyAI LeMUR intelligence + n8n reporting."""
    try:
        # Mark shift as completed in Supabase
        await update_shift_status(shift_id, "completed")

        # Pull real stats to build the intelligence payload
        stats = await get_shift_stats(shift_id)
        sessions = await get_shift_voice_sessions(shift_id)

        # 1. Trigger AssemblyAI LeMUR speech analysis pipeline in background
        background_tasks.add_task(run_shift_intelligence_and_stream, shift_id, current_user.get("id"))

        # 2. Trigger n8n post-shift intelligence notification
        trigger_post_shift_report_background(
            shift_id=shift_id,
            driver_id=current_user["id"],
            driver_name=current_user.get("full_name") or current_user.get("email", "Driver"),
            total_deliveries=stats.get("total", 0),
            delivered_count=stats.get("delivered", 0),
            failed_count=stats.get("failed", 0),
            shift_duration_min=0,
            dispatcher_alerts=0,
            voice_sessions=len(sessions),
            shift_date=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            ended_at=datetime.now(timezone.utc).isoformat(),
        )

        return ShiftEndResponse(
            shift_id=shift_id,
            status="completed",
            message="Shift ended. LeMUR intelligence analysis and reports are being generated."
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
    shift = await get_shift_by_id(shift_id)
    if not shift or shift.get("driver_id") != current_user["id"]:
        raise HTTPException(status_code=404, detail="Shift not found")

    report = await get_intelligence_report_by_shift(shift_id)

    if not report:
        return {"status": "processing", "message": "Report is being generated"}

    report["status"] = "ready"
    if shift.get("started_at"):
        report["shift_started_at"] = shift["started_at"]
    if shift.get("ended_at"):
        report["shift_ended_at"] = shift["ended_at"]

    return report


@router.get("/{shift_id}/stats")
async def get_shift_statistics(
    shift_id: str,
    current_user: dict = Depends(get_current_driver)
):
    """Get shift statistics."""
    stats = await get_shift_stats(shift_id)
    return stats


@router.post("/{shift_id}/analyze-lemur")
async def analyze_shift_lemur(
    shift_id: str,
    current_user: dict = Depends(get_current_driver)
):
    """
    Run AssemblyAI LeMUR intelligence analysis on completed shift transcripts.
    Extracts executive summary, driver sentiment, route issues, and recommendations.
    Persists structured intelligence report directly into Supabase.
    """
    result = await run_shift_intelligence_and_stream(shift_id, current_user.get("id"))
    return result

