from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


class DeliveryStatusUpdate(BaseModel):
    status: str = Field(..., description="Delivery status: pending, delivered, failed, rescheduled")
    notes: Optional[str] = None
    failure_reason: Optional[str] = None


class LocationPing(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


class ConnectPlatformRequest(BaseModel):
    platform: str
    connect_code: Optional[str] = None
    credentials: Optional[dict] = None


class UpdateProfileRequest(BaseModel):
    name: Optional[str] = None
    vehicle_type: Optional[str] = None


class SendOTPRequest(BaseModel):
    phone: str


class VerifyOTPRequest(BaseModel):
    phone: str
    token: str
