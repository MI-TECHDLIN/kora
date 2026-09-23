"""
API routes for driver preferences.

Provides REST endpoints for managing driver behavioral preferences.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from typing import Any, Optional
from app.services.preference_service import preference_service
from app.dependencies import get_current_driver

router = APIRouter(prefix="/preferences", tags=["preferences"])


class PreferenceValue(BaseModel):
    """Model for preference value with type validation."""
    value: Any = Field(..., description="The preference value")


class PreferenceResponse(BaseModel):
    """Response model for preference operations."""
    key: str
    value: Any
    success: bool
    message: Optional[str] = None


class PreferencesListResponse(BaseModel):
    """Response model for listing all preferences."""
    preferences: dict
    success: bool
    message: Optional[str] = None


@router.get("")
async def get_all_preferences(
    driver = Depends(get_current_driver)
) -> PreferencesListResponse:
    """
    Get all preferences for the current driver.
    
    Returns a dictionary of all preference_key -> preference_value.
    """
    try:
        driver_id = driver.get("id") if driver else None
        if not driver_id:
            raise HTTPException(status_code=401, detail="Driver not authenticated")
            
        preferences = await preference_service.get_preferences(driver_id)
        return PreferencesListResponse(
            preferences=preferences,
            success=True,
            message=f"Retrieved {len(preferences)} preferences"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to retrieve preferences: {str(e)}")


@router.get("/{key}")
async def get_preference(
    key: str,
    driver = Depends(get_current_driver)
) -> PreferenceResponse:
    """
    Get a specific preference by key.
    
    Returns the preference value if set, or null if not found.
    """
    try:
        driver_id = driver.get("id") if driver else None
        if not driver_id:
            raise HTTPException(status_code=401, detail="Driver not authenticated")
            
        value = await preference_service.get_preference(driver_id, key)
        return PreferenceResponse(
            key=key,
            value=value,
            success=True,
            message=f"Preference {key} retrieved"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to retrieve preference: {str(e)}")


@router.put("/{key}")
async def set_preference(
    key: str,
    preference: PreferenceValue,
    driver = Depends(get_current_driver)
) -> PreferenceResponse:
    """
    Set a preference for the current driver.
    
    Creates or updates the preference with the given value.
    """
    try:
        driver_id = driver.get("id") if driver else None
        if not driver_id:
            raise HTTPException(status_code=401, detail="Driver not authenticated")
            
        success = await preference_service.set_preference(driver_id, key, preference.value)
        if success:
            return PreferenceResponse(
                key=key,
                value=preference.value,
                success=True,
                message=f"Preference {key} updated successfully"
            )
        else:
            raise HTTPException(status_code=500, detail="Failed to save preference")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to set preference: {str(e)}")


@router.delete("/{key}")
async def clear_preference(
    key: str,
    driver = Depends(get_current_driver)
) -> PreferenceResponse:
    """
    Clear a preference for the current driver.
    
    Removes the preference from storage.
    """
    try:
        driver_id = driver.get("id") if driver else None
        if not driver_id:
            raise HTTPException(status_code=401, detail="Driver not authenticated")
            
        success = await preference_service.clear_preference(driver_id, key)
        if success:
            return PreferenceResponse(
                key=key,
                value=None,
                success=True,
                message=f"Preference {key} cleared successfully"
            )
        else:
            raise HTTPException(status_code=500, detail="Failed to clear preference")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to clear preference: {str(e)}")


@router.delete("")
async def reset_all_preferences(
    driver = Depends(get_current_driver)
) -> PreferencesListResponse:
    """
    Reset all preferences for the current driver.
    
    Deletes all stored preferences, returning to default behavior.
    """
    try:
        driver_id = driver.get("id") if driver else None
        if not driver_id:
            raise HTTPException(status_code=401, detail="Driver not authenticated")
            
        success = await preference_service.reset_preferences(driver_id)
        if success:
            return PreferencesListResponse(
                preferences={},
                success=True,
                message="All preferences reset to defaults"
            )
        else:
            raise HTTPException(status_code=500, detail="Failed to reset preferences")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to reset preferences: {str(e)}")
