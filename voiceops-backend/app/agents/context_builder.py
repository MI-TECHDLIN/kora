"""
VoiceOps Context Builder
Resolves live driver context from JWT + Supabase on every voice session.
Falls back to a safe demo context when token is absent (dev/testing).
"""
import logging
from typing import Optional
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

DEMO_CONTEXT = {
    "driver_id": "demo-driver-001",
    "driver_name": "Demo Driver",
    "shift_id": "demo-shift-001",
    "session_id": "demo-session",
    "is_demo": True,
    "current_delivery": {
        "id": "demo-delivery-001",
        "recipient_name": "Jordan Lee",
        "address": "812 Lavaca St, Austin, TX 78701",
        "customer_phone": "+15125550100",
        "notes": "Gate code is 4521. Call on arrival.",
        "time_window": "10:00 AM - 12:00 PM",
        "latitude": 30.2713,
        "longitude": -97.7455,
    },
}


async def build_driver_context(
    authorization: Optional[str],
    session_id: str,
) -> dict:
    """
    Resolves live driver context from JWT + Supabase.

    Resolution order:
    1. Validate Bearer JWT via Supabase Auth → get user.id
    2. Look up `drivers` table to get name, vehicle, current_shift_id
    3. Look up active `shifts` row to confirm shift_id
    4. Look up next pending `deliveries` row for that shift
    5. Return structured context dict

    Falls back to DEMO_CONTEXT when:
    - No authorization token provided
    - Token is invalid / expired
    - Driver profile not found in DB
    """
    # Lazy imports to avoid circular dependencies at module load time
    from app.db.client import get_supabase_client
    from app.db.queries import (
        get_driver_by_id,
        get_active_shift_for_driver,
        get_next_pending_delivery,
    )

    if not authorization or not authorization.startswith("Bearer "):
        logger.warning("[ContextBuilder] No auth token — using demo context")
        return {**DEMO_CONTEXT, "session_id": session_id}

    token = authorization[7:]

    try:
        supabase = get_supabase_client()
        user_resp = supabase.auth.get_user(token)
        if not user_resp or not user_resp.user:
            logger.warning("[ContextBuilder] Invalid token — using demo context")
            return {**DEMO_CONTEXT, "session_id": session_id}

        user_id = user_resp.user.id

    except Exception as e:
        logger.warning(f"[ContextBuilder] Token validation failed ({e}) — using demo context")
        return {**DEMO_CONTEXT, "session_id": session_id}

    # Fetch driver profile
    driver = await get_driver_by_id(user_id)
    if not driver:
        logger.warning(f"[ContextBuilder] No driver profile for user {user_id} — using demo context")
        return {**DEMO_CONTEXT, "session_id": session_id}

    driver_id = driver["id"]
    driver_name = driver.get("name") or "Driver"

    # Fetch active shift
    shift = await get_active_shift_for_driver(driver_id)
    shift_id = shift["id"] if shift else None

    # Fetch next pending delivery
    current_delivery = None
    if shift_id:
        delivery = await get_next_pending_delivery(shift_id, driver_id)
        if delivery:
            current_delivery = {
                "id": delivery["id"],
                "recipient_name": delivery.get("recipient_name", "Customer"),
                "address": delivery.get("address", ""),
                "customer_phone": delivery.get("phone", ""),
                "notes": delivery.get("notes", ""),
                "time_window": delivery.get("time_window", ""),
                "latitude": delivery.get("latitude"),
                "longitude": delivery.get("longitude"),
                "sequence": delivery.get("sequence_order"),
            }

    context = {
        "driver_id": driver_id,
        "driver_name": driver_name,
        "shift_id": shift_id or "",
        "session_id": session_id,
        "is_demo": False,
        "vehicle_type": driver.get("vehicle_type", ""),
        "driver_status": driver.get("status", "active"),
        "current_delivery": current_delivery,
        "resolved_at": datetime.now(timezone.utc).isoformat(),
    }

    # Inject contextual operational memories (gate codes, location instructions)
    from app.agents.memory_agent import memory_agent
    context = await memory_agent.inject_into_context(context)

    logger.info(
        f"[ContextBuilder] Resolved context for driver {driver_name} "
        f"(shift={shift_id}, delivery={current_delivery['id'] if current_delivery else None})"
    )

    return context
