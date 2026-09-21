from fastapi import APIRouter, HTTPException, status, Depends, Header
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timezone
from app.dependencies import get_current_driver
from app.db.queries import get_driver_by_id
from app.db.client import get_supabase_client
from app.integrations.n8n_client import trigger_driver_onboarding_background


router = APIRouter()


class UpdateProfileRequest(BaseModel):
    name: Optional[str] = None
    vehicle_type: Optional[str] = None
    trigger_onboarding: Optional[bool] = False


class OnboardDriverRequest(BaseModel):
    driver_id: Optional[str] = None
    driver_name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    vehicle_type: Optional[str] = None
    operator_name: Optional[str] = "Kora"


class ConnectPlatformRequest(BaseModel):
    platform: str
    connect_code: Optional[str] = None
    credentials: Optional[dict] = None


@router.get("/profile")
async def get_profile(current_user: dict = Depends(get_current_driver)):
    """Get current driver profile."""
    driver = await get_driver_by_id(current_user["id"])
    if not driver:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Driver profile not found"
        )
    return driver


@router.put("/profile")
async def update_profile(
    request: UpdateProfileRequest,
    current_user: dict = Depends(get_current_driver)
):
    """Update driver profile."""
    supabase = get_supabase_client()
    
    update_data = {}
    if request.name:
        update_data["name"] = request.name
    if request.vehicle_type:
        update_data["vehicle_type"] = request.vehicle_type
    
    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields to update"
        )
    
    try:
        response = (
            supabase.table("drivers")
            .update(update_data)
            .eq("id", current_user["id"])
            .execute()
        )
        
        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Driver profile not found"
            )
        
        return response.data[0]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update profile: {str(e)}"
        )


@router.post("/connect")
async def connect_platform(
    request: ConnectPlatformRequest,
    current_user: dict = Depends(get_current_driver)
):
    """Connect driver to a logistics platform."""
    supabase = get_supabase_client()
    
    # Verify connect code if provided
    if request.connect_code:
        code_response = (
            supabase.table("operator_codes")
            .select("*")
            .eq("code", request.connect_code)
            .eq("active", True)
            .execute()
        )
        
        if not code_response.data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or inactive connect code"
            )
        
        code_info = code_response.data[0]
        platform = code_info["platform"]
    else:
        platform = request.platform
    
    try:
        response = (
            supabase.table("platform_connections")
            .insert({
                "driver_id": current_user["id"],
                "platform": platform,
                "connect_code": request.connect_code,
                "credentials": request.credentials,
                "status": "active"
            })
            .execute()
        )
        
        return {
            "message": "Platform connected successfully",
            "connection": response.data[0] if response.data else None
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to connect platform: {str(e)}"
        )


@router.post("/onboard")
async def onboard_driver(
    request: OnboardDriverRequest,
    authorization: Optional[str] = Header(None)
):
    """
    Trigger driver onboarding workflow (Twilio welcome SMS + operator notifications).
    Supports either an authenticated driver bearer token or direct payload parameters.
    """
    driver_id = request.driver_id
    driver_name = request.driver_name
    phone = request.phone
    email = request.email
    vehicle_type = request.vehicle_type

    # If Authorization header provided, extract driver info from Supabase session
    if authorization and authorization.startswith("Bearer "):
        try:
            supabase = get_supabase_client()
            user_resp = supabase.auth.get_user(authorization[7:])
            if user_resp and user_resp.user:
                u = user_resp.user
                driver_id = driver_id or u.id
                phone = phone or getattr(u, "phone", None)
                email = email or getattr(u, "email", None)
                metadata = getattr(u, "user_metadata", {}) or {}
                driver_name = driver_name or metadata.get("name") or metadata.get("full_name")
        except Exception:
            pass

    # Defaults for onboarding
    driver_id = driver_id or f"drv_{int(datetime.now(timezone.utc).timestamp())}"
    driver_name = driver_name or "Kora Driver"

    # Fire-and-forget onboarding trigger
    trigger_driver_onboarding_background(
        driver_id=driver_id,
        driver_name=driver_name,
        phone=phone,
        email=email,
        vehicle_type=vehicle_type,
        operator_name=request.operator_name or "Kora"
    )

    return {
        "status": "success",
        "message": "Driver onboarding triggered",
        "driver_id": driver_id,
        "driver_name": driver_name,
        "phone": phone
    }

