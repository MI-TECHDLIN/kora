"""
Customer Agent
Specialized communication agent that interfaces with customers.
Enforces permission sandboxing: allowed actions are limited to ETA inquiries,
delivery status confirmation, delivery instructions, and approved callbacks.
"""
import logging
from typing import Dict, Any
from app.db.queries import get_delivery_by_id, is_valid_uuid

logger = logging.getLogger(__name__)


class CustomerAgent:
    ALLOWED_ACTIONS = {
        "send_eta",
        "confirm_status",
        "collect_instructions",
        "schedule_callback",
    }

    async def handle_request(
        self,
        action: str,
        delivery_id: str,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Processes allowed customer communication actions with policy checks.
        """
        if action not in self.ALLOWED_ACTIONS:
            return {
                "success": False,
                "error": f"Action '{action}' is forbidden for CustomerAgent. Contact dispatcher.",
            }

        delivery = await get_delivery_by_id(delivery_id) if is_valid_uuid(delivery_id) else None
        if not delivery:
            return {"success": False, "error": f"Delivery {delivery_id} not found."}

        if action == "confirm_status":
            return {
                "success": True,
                "action": action,
                "status": delivery.get("status", "pending"),
                "estimated_arrival": delivery.get("estimated_arrival"),
                "recipient": delivery.get("recipient_name"),
            }

        elif action == "collect_instructions":
            instructions = payload.get("instructions", "")
            from app.db.queries import get_supabase
            try:
                get_supabase().table("deliveries").update({
                    "notes": instructions
                }).eq("id", delivery_id).execute()
                return {
                    "success": True,
                    "action": action,
                    "message": "Delivery instructions updated for driver.",
                }
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "schedule_callback":
            preferred_time = payload.get("preferred_time", "soon")
            return {
                "success": True,
                "action": action,
                "message": f"Callback request logged for {preferred_time}.",
            }

        return {"success": True, "action": action}


customer_agent = CustomerAgent()
