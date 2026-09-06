from fastapi import APIRouter, HTTPException, status, Depends
from pydantic import BaseModel
from typing import Optional
from app.dependencies import get_current_driver
from app.db.queries import get_driver_by_id
from app.db.client import get_supabase_client


router = APIRouter()


class UpdateProfileRequest(BaseModel):
    name: Optional[str] = None
    vehicle_type: Optional[str] = None


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
