"""
VoiceOps Tool Execution API
Provides parallel tool execution using asyncio.gather() ensuring sub-500ms multi-tool dispatch.
"""
from fastapi import APIRouter, HTTPException, status, Header
from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
from app.agents.orchestrator import ToolOrchestrator

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


@router.post("/execute-parallel", response_model=ParallelToolExecutionResponse)
async def execute_tools_in_parallel(request: ParallelToolExecutionRequest):
    """
    Execute multiple voice assistant tools in parallel using asyncio.gather().
    Keeps overall response time under 500ms SLA.
    """
    tool_dicts = [t.model_dump() for t in request.tools]
    result = await ToolOrchestrator.execute_parallel(tool_dicts, request.context)
    return ParallelToolExecutionResponse(**result)


@router.post("/benchmark")
async def benchmark_tools(request: ParallelToolExecutionRequest):
    """
    Live benchmark comparing sequential execution against parallel asyncio.gather().
    Demonstrates latency reduction and speedup factor.
    """
    tool_dicts = [t.model_dump() for t in request.tools]
    result = await ToolOrchestrator.benchmark_sequential_vs_parallel(tool_dicts, request.context)
    return result
