from fastapi import APIRouter, HTTPException, status, Depends, Header
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timezone
from app.dependencies import get_current_driver
from app.db.queries import get_driver_by_id, create_driver_profile
from app.db.client import get_supabase_client
from app.integrations.n8n_client import trigger_driver_onboarding_background
from app.services.vehicle_modes import (
    VehicleMode,
    invalidate_driver_vehicle_mode,
    parse_vehicle_mode,
)
import logging

logger = logging.getLogger(__name__)


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


@router.post("/ensure-profile")
async def ensure_profile(current_user: dict = Depends(get_current_driver)):
    """
    Idempotently create the signed-in driver's `drivers` row if it doesn't exist yet.
    Safe to call on every sign-in and session restore (kora-full-audit report §2.1).

    Runs with the service-role Supabase client, so creation succeeds regardless of the
    anon-key RLS INSERT policy state. Phone comes from Supabase Auth user_metadata when
    present; Google sign-in never sets one, and drivers.phone is nullable so that no
    longer blocks account setup.
    """
    driver_id = current_user["id"]
    existing = await get_driver_by_id(driver_id)
    if existing:
        return existing

    metadata = current_user.get("user_metadata") or {}
    phone = metadata.get("phone") or current_user.get("phone")
    name = metadata.get("full_name") or metadata.get("name")
    return await create_driver_profile(driver_id, phone=phone, name=name)


@router.get("/profile")
async def get_profile(current_user: dict = Depends(get_current_driver)):
    """Get current driver profile with enhanced data loading and error handling."""
    try:
        driver = await get_driver_by_id(current_user["id"])
        if not driver:
            logger.warning(f"[Driver Profile] Profile not found for user: {current_user.get('id')}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Driver profile not found"
            )
        
        # Ensure all expected fields are present with defaults
        profile = {
            "id": driver.get("id"),
            "name": driver.get("name") or driver.get("full_name") or "Driver",
            "full_name": driver.get("full_name") or driver.get("name") or "Driver",
            "email": driver.get("email") or current_user.get("email", ""),
            "phone": driver.get("phone") or "",
            "vehicle_type": driver.get("vehicle_type") or "vehicle",
            "created_at": driver.get("created_at"),
            "updated_at": driver.get("updated_at"),
            "connect_code": driver.get("connect_code"),
            "platform": driver.get("platform"),
        }
        
        # Add any additional fields that might exist
        for key, value in driver.items():
            if key not in profile:
                profile[key] = value
        
        logger.info(f"[Driver Profile] Successfully loaded profile for driver: {profile.get('id')}")
        return profile
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[Driver Profile] Error loading profile: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to load profile: {str(e)}"
        )


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
        vehicle_type = request.vehicle_type.strip()
        # The vehicle decides how ETAs are computed, so an unrecognised value is
        # rejected here instead of silently being timed as a car later.
        if parse_vehicle_mode(vehicle_type) is None:
            raise HTTPException(
                status_code=422,
                detail=(
                    f"Unrecognised vehicle_type {request.vehicle_type!r}. "
                    f"Use one of: {', '.join(mode.value for mode in VehicleMode)}."
                ),
            )
        update_data["vehicle_type"] = vehicle_type
    
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
        
        invalidate_driver_vehicle_mode(current_user["id"])
        return response.data[0]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update profile: {str(e)}"
        )


@router.post("/signout")
async def sign_out(current_user: dict = Depends(get_current_driver)):
    """Sign out current driver and clear session."""
    try:
        # In a real implementation, this would invalidate the JWT token
        # For now, we'll return success and let the frontend handle session clearing
        logger.info(f"[Driver Sign Out] Driver {current_user.get('id')} signing out")
        
        return {
            "success": True,
            "message": "Signed out successfully",
            "redirect_to": "/welcome"
        }
    except Exception as e:
        logger.error(f"[Driver Sign Out] Error during sign out: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to sign out: {str(e)}"
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

