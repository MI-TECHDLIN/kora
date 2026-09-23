from pydantic import BaseModel, Field
from typing import Literal, Optional, List
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


# Order Intake API: what a logistics platform sends to POST /v1/logistics/orders
# (docs/contracts/interface.md §2). The MockAdapter's order feed builds the same payload.

class OrderRecipient(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    phone: Optional[str] = Field(None, max_length=20)


class OrderDropoff(BaseModel):
    address: str = Field(..., min_length=1)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


class OrderTimeWindow(BaseModel):
    start: datetime
    end: datetime


class OrderDetails(BaseModel):
    recipient: OrderRecipient
    dropoff: OrderDropoff
    notes: Optional[str] = None
    time_window: Optional[OrderTimeWindow] = None
    package_count: Optional[int] = Field(None, ge=1)
    category: Optional[str] = Field(None, max_length=50)
    weight_kg: Optional[float] = Field(None, ge=0)
    dimensions: Optional[dict] = None
    value: Optional[float] = Field(None, ge=0)


class OrderCreatedEvent(BaseModel):
    event: Literal["order.created"]
    source: str = Field(..., min_length=1, max_length=100, description="The sending platform")
    external_id: str = Field(..., min_length=1, max_length=100, description="The platform's order id")
    created_at: Optional[datetime] = None
    order: OrderDetails
