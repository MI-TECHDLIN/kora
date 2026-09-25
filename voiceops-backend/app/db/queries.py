from typing import Optional, Dict, List, Any
import re
import logging

logger = logging.getLogger(__name__)

UUID_REGEX = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', re.IGNORECASE)


def is_valid_uuid(val: Any) -> bool:
    return bool(val and isinstance(val, str) and UUID_REGEX.match(val))


def get_supabase():
    """Lazy import to avoid circular dependency."""
    from app.db.client import get_supabase_client
    return get_supabase_client()


async def get_driver_by_id(driver_id: str) -> Optional[Dict[str, Any]]:
    """Get driver by ID with enhanced error handling and field validation."""
    if not is_valid_uuid(driver_id):
        logger.warning(f"[DB Queries] Invalid driver ID format: {driver_id}")
        return None
    
    try:
        supabase = get_supabase()
        response = supabase.table("drivers").select("*").eq("id", driver_id).execute()
        
        if response.data:
            driver = response.data[0]
            # Ensure critical fields exist
            if not driver.get("id"):
                logger.warning(f"[DB Queries] Driver record missing ID field: {driver_id}")
                return None
            
            # Normalize common field names for consistency
            if "full_name" not in driver and "name" in driver:
                driver["full_name"] = driver["name"]
            if "name" not in driver and "full_name" in driver:
                driver["name"] = driver["full_name"]
            
            return driver
        else:
            logger.warning(f"[DB Queries] Driver not found: {driver_id}")
            return None
    except Exception as e:
        logger.error(f"[DB Queries] Error fetching driver {driver_id}: {e}")
        return None


async def create_driver_profile(
    driver_id: str, *, phone: Optional[str] = None, name: Optional[str] = None
) -> Dict[str, Any]:
    """Idempotently insert a `drivers` row for an already-authenticated Supabase user.

    Runs with the service-role client (see app/db/client.py), so it is not subject to
    the anon-key RLS INSERT policy (kora-full-audit report §2.1). `phone` is optional:
    Google sign-in never puts one in user_metadata, and drivers.phone is nullable.
    Safe to call concurrently — a duplicate-key error on the `id` primary key (another
    call won the race) is treated as success, not a failure.
    """
    existing = await get_driver_by_id(driver_id)
    if existing:
        return existing
    try:
        response = (
            get_supabase().table("drivers")
            .insert({"id": driver_id, "phone": phone, "name": name})
            .execute()
        )
        return response.data[0] if response.data else await get_driver_by_id(driver_id)
    except Exception:
        existing = await get_driver_by_id(driver_id)
        if existing:
            return existing
        raise


async def get_next_pending_delivery(shift_id: str, driver_id: str) -> Optional[Dict[str, Any]]:
    """Get next pending delivery for a shift."""
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


async def get_active_shift_for_driver(driver_id: str) -> Optional[Dict[str, Any]]:
    """Get the currently active (non-completed) shift for a driver."""
    if not is_valid_uuid(driver_id):
        return None
    try:
        response = (
            get_supabase().table("shifts")
            .select("*")
            .eq("driver_id", driver_id)
            .eq("status", "active")
            .order("started_at", desc=True)
            .limit(1)
            .execute()
        )
        if response.data:
            return response.data[0]
        return None
    except Exception:
        return None


async def get_delivery_by_id(delivery_id: str) -> Optional[Dict[str, Any]]:
    """Get a single delivery by its ID."""
    if not is_valid_uuid(delivery_id):
        return None
    try:
        response = (
            get_supabase().table("deliveries")
            .select("*")
            .eq("id", delivery_id)
            .limit(1)
            .execute()
        )
        if response.data:
            return response.data[0]
        return None
    except Exception:
        return None


async def mark_delivery_status(
    delivery_id: str,
    status: str,
    failure_reason: Optional[str] = None,
    notes: Optional[str] = None
) -> Dict[str, Any]:
    """Update delivery status."""
    update_data: Dict[str, Any] = {"status": status}
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


async def create_delivery_event(
    delivery_id: str,
    driver_id: str,
    event_type: str,
    status_before: Optional[str] = None,
    status_after: Optional[str] = None,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    metadata: Optional[dict] = None,
) -> Dict[str, Any]:
    """
    Insert an immutable delivery_events record.
    Used for audit trail, analytics, and idempotency checks.
    """
    if not is_valid_uuid(delivery_id):
        return {}
    try:
        row: Dict[str, Any] = {
            "delivery_id": delivery_id,
            "driver_id": driver_id if is_valid_uuid(driver_id) else None,
            "event_type": event_type,
        }
        if status_before is not None:
            row["status_before"] = status_before
        if status_after is not None:
            row["status_after"] = status_after
        if latitude is not None:
            row["latitude"] = latitude
        if longitude is not None:
            row["longitude"] = longitude
        if metadata:
            row["metadata"] = metadata

        response = get_supabase().table("delivery_events").insert(row).execute()
        return response.data[0] if response.data else {}
    except Exception as e:
        import logging
        logging.getLogger(__name__).error(f"[DB] create_delivery_event failed: {e}")
        return {}


async def increment_delivery_attempts(delivery_id: str) -> Dict[str, Any]:
    """Increment attempt_count on a delivery by 1."""
    if not is_valid_uuid(delivery_id):
        return {}
    try:
        delivery = await get_delivery_by_id(delivery_id)
        if not delivery:
            return {}
        new_count = (delivery.get("attempt_count") or 0) + 1
        response = (
            get_supabase().table("deliveries")
            .update({"attempt_count": new_count})
            .eq("id", delivery_id)
            .execute()
        )
        return response.data[0] if response.data else {}
    except Exception:
        return {}


async def save_location_ping(
    driver_id: str,
    shift_id: str,
    lat: float,
    lng: float,
    speed: float = 0.0,
    heading: float = 0.0,
    accuracy: float = 0.0,
) -> Dict[str, Any]:
    """Save a GPS location ping to location_pings table."""
    try:
        data = {
            "driver_id": driver_id if is_valid_uuid(driver_id) else None,
            "shift_id": shift_id if is_valid_uuid(shift_id) else None,
            "latitude": lat,
            "longitude": lng,
            "pinged_at": "now()",
        }
        response = get_supabase().table("location_pings").insert(data).execute()
        return response.data[0] if response.data else {}
    except Exception as e:
        import logging
        logging.getLogger(__name__).error(f"[DB] save_location_ping failed: {e}")
        return {}


async def update_driver_location(
    driver_id: str,
    lat: float,
    lng: float,
    heading: float = 0.0,
    speed: float = 0.0,
) -> Dict[str, Any]:
    """Update the driver's live position fields on the drivers table."""
    if not is_valid_uuid(driver_id):
        return {}
    try:
        response = (
            get_supabase().table("drivers")
            .update({
                "current_latitude": lat,
                "current_longitude": lng,
                "current_heading": heading,
                "current_speed": speed,
            })
            .eq("id", driver_id)
            .execute()
        )
        return response.data[0] if response.data else {}
    except Exception:
        return {}


async def get_recent_location_pings(
    driver_id: str,
    limit: int = 10,
) -> List[Dict[str, Any]]:
    """Return the most recent GPS pings for a driver (latest first)."""
    if not is_valid_uuid(driver_id):
        return []
    try:
        response = (
            get_supabase().table("location_pings")
            .select("*")
            .eq("driver_id", driver_id)
            .order("pinged_at", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data if response.data else []
    except Exception:
        return []


async def create_voice_session(shift_id: str, driver_id: str, delivery_id: Optional[str] = None) -> str:
    """Create a voice session and return session_id."""
    response = (
        get_supabase().table("voice_sessions")
        .insert({
            "shift_id": shift_id,
            "driver_id": driver_id,
            "delivery_id": delivery_id,
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


async def save_location_ping(
    driver_id: str,
    shift_id: str,
    lat: float,
    lng: float,
    speed: float = 0.0,
    heading: float = 0.0,
    accuracy: float = 0.0,
) -> Dict[str, Any]:
    """Save GPS location ping with full telemetry fields."""
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
        return {"total": 0, "delivered": 0, "failed": 0, "success_rate": 0}
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
        pending = sum(1 for d in deliveries if d["status"] == "pending")
        en_route = sum(1 for d in deliveries if d["status"] == "en_route")

        return {
            "total": total,
            "delivered": delivered,
            "failed": failed,
            "pending": pending,
            "en_route": en_route,
            "remaining": total - delivered - failed,
            "success_rate": (delivered / total * 100) if total > 0 else 0,
        }
    except Exception:
        return {"total": 0, "delivered": 0, "failed": 0, "success_rate": 0}


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

    response = (
        get_supabase().table("intelligence_reports")
        .select("*")
        .eq("shift_id", shift_id)
        .order("generated_at", desc=True)
        .limit(1)
        .execute()
    )
    if response.data:
        return response.data[0]
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


# ---------------------------------------------------------------------------- order dispatch
# A new order is a `deliveries` row with shift_id NULL and one of these statuses until a driver
# accepts it; acceptance sets shift_id and flips it to `pending` (docs/contracts/interface.md §3).
OPEN_ORDER_STATUSES = ("offered", "unassigned")


async def get_delivery_by_external_id(source: str, external_id: str) -> Optional[Dict[str, Any]]:
    """The delivery a platform's order already became, if any (Order Intake is idempotent)."""
    response = (
        get_supabase().table("deliveries")
        .select("*")
        .eq("source", source)
        .eq("external_id", external_id)
        .limit(1)
        .execute()
    )
    return response.data[0] if response.data else None


async def insert_incoming_order(fields: Dict[str, Any]) -> Dict[str, Any]:
    """Store a new, unassigned order (shift_id NULL). `fields` must carry an OPEN_ORDER_STATUSES status."""
    response = get_supabase().table("deliveries").insert({**fields, "shift_id": None}).execute()
    return response.data[0] if response.data else {}


async def set_open_order_status(delivery_id: str, status: str) -> Dict[str, Any]:
    """Move an order between `offered` and `unassigned`; never touches an order a driver has."""
    response = (
        get_supabase().table("deliveries")
        .update({"status": status})
        .eq("id", delivery_id)
        .is_("shift_id", "null")
        .execute()
    )
    return response.data[0] if response.data else {}


async def assign_order_to_shift(delivery_id: str, shift_id: str) -> Optional[Dict[str, Any]]:
    """
    Give an open order to a shift as its last stop: shift_id set, status `pending`, next
    sequence_order. Returns None when the order is no longer open (someone else got it).
    """
    last = (
        get_supabase().table("deliveries")
        .select("sequence_order")
        .eq("shift_id", shift_id)
        .order("sequence_order", desc=True, nullsfirst=False)
        .limit(1)
        .execute()
    )
    last_sequence = (last.data[0].get("sequence_order") if last.data else None) or 0
    response = (
        get_supabase().table("deliveries")
        .update({"shift_id": shift_id, "status": "pending", "sequence_order": last_sequence + 1})
        .eq("id", delivery_id)
        .is_("shift_id", "null")
        .in_("status", list(OPEN_ORDER_STATUSES))
        .execute()
    )
    return response.data[0] if response.data else None


async def get_open_orders() -> List[Dict[str, Any]]:
    """Orders no driver has yet, oldest first (reloaded into the dispatcher on startup)."""
    response = (
        get_supabase().table("deliveries")
        .select("*")
        .is_("shift_id", "null")
        .in_("status", list(OPEN_ORDER_STATUSES))
        .order("created_at")
        .execute()
    )
    return response.data or []


async def get_active_driver_positions() -> List[Dict[str, Any]]:
    """
    Every active shift with its driver's name and latest GPS ping: the dispatch candidates.
    `latitude` / `longitude` / `pinged_at` are None for a shift with no ping yet.
    """
    supabase = get_supabase()
    shifts = (
        supabase.table("shifts")
        .select("id, driver_id, started_at, drivers(name)")
        .eq("status", "active")
        .execute()
    ).data or []
    if not shifts:
        return []

    # Newest first, so the first ping seen per shift is its latest. PostgREST has no DISTINCT ON;
    # at fleet scale this wants a view or RPC instead of the row cap.
    pings = (
        supabase.table("location_pings")
        .select("shift_id, latitude, longitude, pinged_at")
        .in_("shift_id", [s["id"] for s in shifts])
        .order("pinged_at", desc=True)
        .limit(1000)
        .execute()
    ).data or []
    latest: Dict[str, Dict[str, Any]] = {}
    for ping in pings:
        latest.setdefault(ping["shift_id"], ping)

    positions = []
    for shift in shifts:
        ping = latest.get(shift["id"]) or {}
        positions.append({
            "driver_id": shift["driver_id"],
            "shift_id": shift["id"],
            "driver_name": (shift.get("drivers") or {}).get("name"),
            "latitude": ping.get("latitude"),
            "longitude": ping.get("longitude"),
            "pinged_at": ping.get("pinged_at"),
        })
    return positions


async def create_shift(driver_id: str) -> Dict[str, Any]:
    """Create a new shift."""
    response = (
        get_supabase().table("shifts")
        .insert({
            "driver_id": driver_id,
            "status": "active",
        })
        .execute()
    )
    return response.data[0] if response.data else {}
