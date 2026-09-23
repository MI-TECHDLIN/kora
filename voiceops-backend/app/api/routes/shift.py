import logging

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
    get_shift_by_id,
    get_active_shift_for_driver,
    get_supabase,
)
from app.integrations.n8n_client import trigger_post_shift_report_background
from app.intelligence.lemur_pipeline import run_shift_intelligence
from app.api.websocket.voice import stream_summary
from app.services.order_queue_service import build_queue_snapshot

logger = logging.getLogger(__name__)

router = APIRouter()


async def run_shift_intelligence_and_stream(shift_id: str, driver_id: str) -> dict:
    """Run the LeMUR pipeline, then stream its summary to the shift's open voice socket."""
    result = await run_shift_intelligence(shift_id, driver_id)
    await stream_summary(shift_id, result.get("analysis", {}).get("executive_summary", ""))
    return result


async def end_shift_core(shift_id: str, driver_id: str, driver_name: str) -> dict:
    """
    Mark a shift completed, persist its stats/timestamps, and fire the n8n post-shift
    webhook. Shared by the `/end` route, the `end_shift` voice tool, and the dangling-shift
    cleanup `/start` runs. Callers are responsible for scheduling
    `run_shift_intelligence_and_stream(shift_id, driver_id)` in the background - this
    function only does the fast, synchronous bookkeeping.
    """
    await update_shift_status(shift_id, "completed")

    shift = await get_shift_by_id(shift_id)
    shift_duration_min = 0
    ended_at_str = datetime.now(timezone.utc).isoformat()

    if shift and shift.get("started_at"):
        try:
            started_dt = datetime.fromisoformat(str(shift["started_at"]).replace("Z", "+00:00"))
            shift_duration_min = max(0, int((datetime.now(timezone.utc) - started_dt).total_seconds() / 60))
        except Exception:
            shift_duration_min = 0

    try:
        get_supabase().table("shifts").update({"ended_at": ended_at_str}).eq("id", shift_id).execute()
    except Exception:
        logger.warning(f"[end_shift_core] failed to persist ended_at for shift {shift_id}", exc_info=True)

    stats = await get_shift_stats(shift_id)
    sessions = await get_shift_voice_sessions(shift_id)

    trigger_post_shift_report_background(
        shift_id=shift_id,
        driver_id=driver_id,
        driver_name=driver_name,
        total_deliveries=stats.get("total", 0),
        delivered_count=stats.get("delivered", 0),
        failed_count=stats.get("failed", 0),
        shift_duration_min=shift_duration_min,
        dispatcher_alerts=0,
        voice_sessions=len(sessions),
        shift_date=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        ended_at=ended_at_str,
    )

    return {
        "shift_id": shift_id,
        "status": "completed",
        "shift_duration_min": shift_duration_min,
    }


class ShiftStartResponse(BaseModel):
    shift_id: str
    status: str
    message: str


class ShiftEndResponse(BaseModel):
    shift_id: str
    status: str
    message: str


@router.get("/{shift_id}/queue")
async def get_shift_queue(
    shift_id: str,
    current_user: dict = Depends(get_current_driver),
):
    """Return the driver-facing queue, including completed stops and daily target."""
    shift = await get_shift_by_id(shift_id)
    if not shift or str(shift.get("driver_id")) != str(current_user["id"]):
        raise HTTPException(status_code=404, detail="Shift not found")
    return await build_queue_snapshot(shift_id, str(current_user["id"]))


@router.post("/start", response_model=ShiftStartResponse)
async def start_shift(
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_driver)
):
    """
    Start a new shift.

    A driver can end up here with a shift still marked `active` from a previous session
    that was never explicitly ended (app killed, connection lost, etc.). Starting a new
    shift on top of a dangling one would let two "active" shifts coexist and would orphan
    the old one's report forever, so we implicitly close it first - same pipeline as a
    normal end, including its own post-shift report - before creating the new shift.
    """
    try:
        driver_id = current_user["id"]

        dangling = await get_active_shift_for_driver(driver_id)
        if dangling and dangling.get("id"):
            try:
                await end_shift_core(
                    dangling["id"],
                    driver_id,
                    current_user.get("full_name") or current_user.get("email", "Driver"),
                )
                background_tasks.add_task(run_shift_intelligence_and_stream, dangling["id"], driver_id)
            except Exception:
                # Don't let cleanup of a stale shift block starting the new one.
                logger.warning(
                    f"[start_shift] failed to auto-close dangling shift {dangling['id']}", exc_info=True
                )

        shift = await create_shift(driver_id)
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
        result = await end_shift_core(
            shift_id,
            current_user["id"],
            current_user.get("full_name") or current_user.get("email", "Driver"),
        )

        # Trigger AssemblyAI LeMUR speech analysis pipeline in background
        background_tasks.add_task(run_shift_intelligence_and_stream, shift_id, current_user.get("id"))

        return ShiftEndResponse(
            shift_id=shift_id,
            status=result["status"],
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

    if shift.get("started_at") and shift.get("ended_at"):
        try:
            started = datetime.fromisoformat(str(shift["started_at"]).replace("Z", "+00:00"))
            ended = datetime.fromisoformat(str(shift["ended_at"]).replace("Z", "+00:00"))
            report["shift_duration_min"] = max(0, int((ended - started).total_seconds() / 60))
        except Exception:
            pass

    # Expose lemur_source and is_estimated at top-level
    if "lemur_source" not in report:
        report["lemur_source"] = (report.get("failure_patterns") or {}).get("lemur_source") or "assemblyai_lemur_api"
    if "is_estimated" not in report:
        report["is_estimated"] = (report.get("failure_patterns") or {}).get("is_estimated", report["lemur_source"] == "voiceops_speech_intelligence_engine")

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
