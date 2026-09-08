from fastapi import APIRouter, HTTPException, status, Depends, BackgroundTasks
from pydantic import BaseModel
from app.dependencies import get_current_driver
from app.db.queries import (
    create_shift,
    update_shift_status,
    get_shift_stats,
    get_intelligence_report_by_shift
)


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
    """End shift and trigger intelligence pipeline."""
    try:
        # Update shift status
        await update_shift_status(shift_id, "completed")
        
        # TODO: Intelligence pipeline removed - add back if needed
        # background_tasks.add_task(
        #     run_shift_intelligence,
        #     shift_id,
        #     current_user["id"]
        # )
        
        return ShiftEndResponse(
            shift_id=shift_id,
            status="completed",
            message="Shift ended successfully."
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
