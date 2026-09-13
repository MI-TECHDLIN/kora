from typing import Optional, Dict, List, Any
import re

UUID_REGEX = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', re.IGNORECASE)


def is_valid_uuid(val: Any) -> bool:
    return bool(val and isinstance(val, str) and UUID_REGEX.match(val))


def get_supabase():
    """Lazy import to avoid circular dependency."""
    from app.db.client import get_supabase_client
    return get_supabase_client()


async def get_driver_by_id(driver_id: str) -> Optional[Dict[str, Any]]:
    """Get driver by ID."""
    supabase = get_supabase()
    response = supabase.table("drivers").select("*").eq("id", driver_id).execute()
    if response.data:
        return response.data[0]
    return None


async def get_next_pending_delivery(shift_id: str, driver_id: str) -> Optional[Dict[str, Any]]:
    """Get next pending delivery for a shift."""
    supabase = get_supabase()
    response = (
        get_supabase().table("deliveries")
        .select("*")
        .eq("shift_id", shift_id)
        .eq("status", "pending")
        .order("sequence_order")
        .limit(1)
        .execute()
    )
    if response.data:
        return response.data[0]
    return None


async def mark_delivery_status(
    delivery_id: str,
    status: str,
    failure_reason: Optional[str] = None,
    notes: Optional[str] = None
) -> Dict[str, Any]:
    """Update delivery status."""
    update_data = {"status": status}
    if failure_reason:
        update_data["failure_reason"] = failure_reason
    if notes:
        update_data["notes"] = notes
    
    response = (
        get_supabase().table("deliveries")
        .update(update_data)
        .eq("id", delivery_id)
        .execute()
    )
    return response.data[0] if response.data else {}


async def create_voice_session(shift_id: str, driver_id: str, delivery_id: Optional[str] = None) -> str:
    """Create a voice session and return session_id."""
    response = (
        get_supabase().table("voice_sessions")
        .insert({
            "shift_id": shift_id,
            "driver_id": driver_id,
            "delivery_id": delivery_id,
            "started_at": "now()"
        })
        .execute()
    )
    return response.data[0]["id"] if response.data else ""


async def update_voice_session(
    session_id: str,
    ended: bool = False,
    driver_transcript: Optional[str] = None,
    agent_transcript: Optional[str] = None
) -> Dict[str, Any]:
    """Update voice session with transcripts and end status."""
    update_data = {}
    if ended:
        update_data["ended_at"] = "now()"
    if driver_transcript:
        update_data["driver_transcript"] = driver_transcript
    if agent_transcript:
        update_data["agent_transcript"] = agent_transcript
    
    response = (
        get_supabase().table("voice_sessions")
        .update(update_data)
        .eq("id", session_id)
        .execute()
    )
    return response.data[0] if response.data else {}


async def log_tool_execution(session_id: str, tool_calls: List[Dict], results: List[Dict]) -> Dict[str, Any]:
    """Log tool execution to voice session."""
    response = (
        get_supabase().table("voice_sessions")
        .update({
            "tool_calls": tool_calls,
            "tool_results": results
        })
        .eq("id", session_id)
        .execute()
    )
    return response.data[0] if response.data else {}


async def save_location_ping(driver_id: str, shift_id: str, lat: float, lng: float) -> Dict[str, Any]:
    """Save GPS location ping."""
    response = (
        get_supabase().table("location_pings")
        .insert({
            "driver_id": driver_id,
            "shift_id": shift_id,
            "latitude": lat,
            "longitude": lng,
            "pinged_at": "now()"
        })
        .execute()
    )
    return response.data[0] if response.data else {}


async def get_shift_voice_sessions(shift_id: str) -> List[Dict[str, Any]]:
    """Get all voice sessions for a shift."""
    if not is_valid_uuid(shift_id):
        return []
    try:
        response = (
            get_supabase().table("voice_sessions")
            .select("*")
            .eq("shift_id", shift_id)
            .order("started_at")
            .execute()
        )
        return response.data if response.data else []
    except Exception:
        return []


async def get_shift_stats(shift_id: str) -> Dict[str, Any]:
    """Get shift statistics."""
    if not is_valid_uuid(shift_id):
        return {
            "total": 0,
            "delivered": 0,
            "failed": 0,
            "success_rate": 0
        }
    try:
        deliveries_response = (
            get_supabase().table("deliveries")
            .select("status")
            .eq("shift_id", shift_id)
            .execute()
        )
        
        deliveries = deliveries_response.data if deliveries_response.data else []
        total = len(deliveries)
        delivered = sum(1 for d in deliveries if d["status"] == "delivered")
        failed = sum(1 for d in deliveries if d["status"] == "failed")
        
        return {
            "total": total,
            "delivered": delivered,
            "failed": failed,
            "success_rate": (delivered / total * 100) if total > 0 else 0
        }
    except Exception:
        return {
            "total": 0,
            "delivered": 0,
            "failed": 0,
            "success_rate": 0
        }


async def get_shift_by_id(shift_id: str) -> Optional[Dict[str, Any]]:
    """Get a shift row. Errors propagate so callers can tell "missing" from "DB down"."""
    if not is_valid_uuid(shift_id):
        return None
    response = get_supabase().table("shifts").select("*").eq("id", shift_id).execute()
    if response.data:
        return response.data[0]
    return None


async def get_latest_location(shift_id: str) -> Optional[Dict[str, Any]]:
    """Get the most recent GPS ping for a shift."""
    if not is_valid_uuid(shift_id):
        return None
    response = (
        get_supabase().table("location_pings")
        .select("latitude, longitude, pinged_at")
        .eq("shift_id", shift_id)
        .order("pinged_at", desc=True)
        .limit(1)
        .execute()
    )
    if response.data:
        return response.data[0]
    return None


async def get_intelligence_report_by_shift(shift_id: str) -> Optional[Dict[str, Any]]:
    """Get intelligence report for a shift."""
    if not is_valid_uuid(shift_id):
        return None
    try:
        response = (
            get_supabase().table("intelligence_reports")
            .select("*")
            .eq("shift_id", shift_id)
            .execute()
        )
        if response.data:
            return response.data[0]
        return None
    except Exception:
        return None



async def store_intelligence_report(shift_id: str, report_dict: Dict[str, Any]) -> Dict[str, Any]:
    """Store intelligence report."""
    response = (
        get_supabase().table("intelligence_reports")
        .insert({
            "shift_id": shift_id,
            **report_dict,
            "generated_at": "now()"
        })
        .execute()
    )
    return response.data[0] if response.data else {}


async def update_shift_status(shift_id: str, status: str) -> Dict[str, Any]:
    """Update shift status."""
    if not is_valid_uuid(shift_id):
        return {}
    try:
        response = (
            get_supabase().table("shifts")
            .update({"status": status})
            .eq("id", shift_id)
            .execute()
        )
        return response.data[0] if response.data else {}
    except Exception:
        return {}


async def get_shift_deliveries(shift_id: str) -> List[Dict[str, Any]]:
    """Get all deliveries for a shift."""
    if not is_valid_uuid(shift_id):
        return []
    try:
        response = (
            get_supabase().table("deliveries")
            .select("*")
            .eq("shift_id", shift_id)
            .order("sequence_order")
            .execute()
        )
        return response.data if response.data else []
    except Exception:
        return []


async def create_shift(driver_id: str) -> Dict[str, Any]:
    """Create a new shift."""
    response = (
        get_supabase().table("shifts")
        .insert({
            "driver_id": driver_id,
            "status": "active",
            "started_at": "now()"
        })
        .execute()
    )
    return response.data[0] if response.data else {}
