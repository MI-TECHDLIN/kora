from fastapi import APIRouter
from pydantic import BaseModel
import asyncio
from datetime import datetime
import time


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
