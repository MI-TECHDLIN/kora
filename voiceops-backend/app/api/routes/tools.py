"""
VoiceOps Tool Execution API
Provides parallel tool execution using asyncio.gather() ensuring sub-500ms multi-tool dispatch.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
from app.agents.orchestrator import ToolOrchestrator
from app.config import settings
from app.db.queries import get_active_shift_for_driver, get_next_pending_delivery
from app.dependencies import get_current_driver

router = APIRouter()


class ToolCallItem(BaseModel):
    name: str = Field(..., description="Name of the tool to execute")
    arguments: Optional[Dict[str, Any]] = Field(default_factory=dict, description="Arguments for tool")
    call_id: Optional[str] = Field(None, description="Optional call ID for tracking")


class ParallelToolExecutionRequest(BaseModel):
    tools: List[ToolCallItem]
    context: Optional[Dict[str, Any]] = Field(default_factory=dict, description="Driver and shift context")


class ParallelToolExecutionResponse(BaseModel):
    tool_count: int
    total_duration_ms: float
    sequential_sum_ms: float
    time_saved_ms: float
    under_500ms: bool
    results: List[Dict[str, Any]]


_CALLER_CONTEXT_FIELDS = {
    "latitude",
    "longitude",
    "current_latitude",
    "current_longitude",
    "eta_minutes",
    "location",
    "trace_id",
}


async def _server_tool_context(caller_context: Dict[str, Any], current_user: dict) -> dict:
    """Build identity and active-work context from authenticated server-side data."""
    driver_id = str(current_user["id"])
    shift = await get_active_shift_for_driver(driver_id)
    shift_id = str(shift["id"]) if shift and shift.get("id") else ""
    current_delivery = (
        await get_next_pending_delivery(shift_id, driver_id)
        if shift_id
        else None
    )
    metadata = current_user.get("user_metadata") or {}

    # Location and trace hints may come from the caller. Identity, demo mode, shift,
    # delivery, session, and profile fields are deliberately not copied.
    context = {
        key: value
        for key, value in caller_context.items()
        if key in _CALLER_CONTEXT_FIELDS
    }
    context.update({
        "driver_id": driver_id,
        "driver_name": (
            current_user.get("full_name")
            or metadata.get("full_name")
            or metadata.get("name")
            or current_user.get("email")
            or "Driver"
        ),
        "shift_id": shift_id,
        "is_demo": False,
        "current_delivery": current_delivery,
    })
    return context


@router.post("/execute-parallel", response_model=ParallelToolExecutionResponse)
async def execute_tools_in_parallel(
    request: ParallelToolExecutionRequest,
    current_user: dict = Depends(get_current_driver),
):
    """
    Execute multiple voice assistant tools in parallel using asyncio.gather().
    Keeps overall response time under 500ms SLA.
    """
    tool_dicts = [t.model_dump() for t in request.tools]
    context = await _server_tool_context(request.context or {}, current_user)
    result = await ToolOrchestrator.execute_parallel(tool_dicts, context)
    return ParallelToolExecutionResponse(**result)


@router.post("/benchmark")
async def benchmark_tools(
    request: ParallelToolExecutionRequest,
    current_user: dict = Depends(get_current_driver),
):
    """
    Live benchmark comparing sequential execution against parallel asyncio.gather().
    Demonstrates latency reduction and speedup factor.
    """
    if settings.environment != "development" or not settings.tools_benchmark_enabled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    tool_dicts = [t.model_dump() for t in request.tools]
    context = await _server_tool_context(request.context or {}, current_user)
    result = await ToolOrchestrator.benchmark_sequential_vs_parallel(tool_dicts, context)
    return result
