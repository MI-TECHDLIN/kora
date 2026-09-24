"""
Route Calculation API Routes
Provides directions, turn-by-turn steps, and distance/ETA computations.
"""
from typing import Optional, List
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from app.dependencies import get_current_driver
from app.api.ownership import require_owned_shift
from app.services.routing_service import routing_service
from app.services.vehicle_modes import get_driver_vehicle_mode

router = APIRouter()


class RouteRequest(BaseModel):
    origin_lat: float = Field(..., ge=-90.0, le=90.0)
    origin_lng: float = Field(..., ge=-180.0, le=180.0)
    dest_lat: float = Field(..., ge=-90.0, le=90.0)
    dest_lng: float = Field(..., ge=-180.0, le=180.0)


@router.post("/routes/calculate")
async def calculate_route_endpoint(
    req: RouteRequest,
    current_user: dict = Depends(get_current_driver),
):
    """Calculate a route between two GPS coordinates, timed for the driver's vehicle."""
    try:
        mode = await get_driver_vehicle_mode(current_user.get("id"))
        route = await routing_service.calculate_route(
            (req.origin_lat, req.origin_lng),
            (req.dest_lat, req.dest_lng),
            vehicle_type=mode.value,
        )
        return route
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Route calculation failed: {str(e)}")


class OptimizeRouteRequest(BaseModel):
    origin_lat: float = Field(..., ge=-90.0, le=90.0)
    origin_lng: float = Field(..., ge=-180.0, le=180.0)
    shift_id: str


@router.post("/routes/optimize")
async def optimize_route_endpoint(
    req: OptimizeRouteRequest,
    current_user: dict = Depends(get_current_driver),
):
    """Reorder pending deliveries for minimal mileage and transit time."""
    from app.services.optimization_service import optimization_service
    from app.db.queries import get_shift_deliveries

    driver_id = current_user.get("id")
    await require_owned_shift(req.shift_id, driver_id, allow_mock_id=True)
    deliveries = await get_shift_deliveries(req.shift_id)

    pending = [d for d in deliveries if d.get("status") in ["pending", "en_route"]]
    if not pending:
        return {"optimized_deliveries": deliveries, "message": "No pending deliveries to optimize."}

    try:
        optimized = await optimization_service.optimize_route(
            driver_id=driver_id,
            shift_id=req.shift_id,
            deliveries=pending,
            origin=(req.origin_lat, req.origin_lng),
        )
        return {"optimized_deliveries": optimized, "count": len(optimized)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Optimization failed: {str(e)}")
