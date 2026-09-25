from fastapi import APIRouter
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import asyncio
from datetime import datetime
import time

from app.services.voice_readiness import readiness_report


router = APIRouter()


class HealthResponse(BaseModel):
    status: str
    timestamp: str
    uptime_seconds: float


# Track startup time
startup_time = time.time()


@router.get("", response_model=HealthResponse)
async def health_check():
    """
    Health check endpoint for Render monitoring.
    Returns status with timestamp to prevent instance sleep.
    """
    return {
        "status": "ok",
        "timestamp": datetime.utcnow().isoformat(),
        "uptime_seconds": time.time() - startup_time
    }


@router.get("/ping")
async def ping():
    """
    Simple ping endpoint for quick health checks.
    """
    return {"ping": "pong", "timestamp": datetime.utcnow().isoformat()}


@router.get("/ready")
async def ready():
    """
    Whether the voice path can start, as booleans and fixed reason tokens only (no values).

    Reports which settings the voice path needs are present, and probes the database and the
    AssemblyAI Voice Agent session (bounded, cached for 30s). 200 when everything is ready, 503
    otherwise. Render's own health check should keep using `/health`.
    """
    report = await readiness_report()
    return JSONResponse(report, status_code=200 if report["ready"] else 503)
