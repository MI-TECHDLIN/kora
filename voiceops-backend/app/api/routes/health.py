from fastapi import APIRouter
from pydantic import BaseModel


router = APIRouter()


class HealthResponse(BaseModel):
    status: str


@router.get("", response_model=HealthResponse)
async def health_check():
    return {"status": "ok"}
