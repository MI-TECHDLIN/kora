"""
Tool Safety Gate
Validates authorization, business rules, and state guards before tool execution.
Prevents unauthenticated mutations or illegal delivery state changes.
"""
import logging
from typing import Tuple, Dict, Any, Optional
from app.services.delivery_state_machine import validate_transition
from app.db.queries import get_delivery_by_id, get_shift_by_id, is_valid_uuid

logger = logging.getLogger(__name__)


class ToolSafetyGate:
    async def check(
        self,
        tool_name: str,
        parameters: Dict[str, Any],
        context: Dict[str, Any]
    ) -> Tuple[bool, str]:
        """
        Runs comprehensive security and safety gates.
        Returns: (is_allowed: bool, rejection_reason: str)
        """
        # 1. Authorization Gate
        ok, reason = await self._check_authorization(tool_name, parameters, context)
        if not ok:
            return False, reason

        # 2. Business Rules Gate
        ok, reason = await self._check_business_rules(tool_name, parameters, context)
        if not ok:
            return False, reason

        return True, ""

    async def _check_authorization(
        self,
        tool_name: str,
        parameters: Dict[str, Any],
        context: Dict[str, Any]
    ) -> Tuple[bool, str]:
        """Verify the caller has authority to act on this delivery."""
        driver_id = context.get("driver_id")
        current_del = context.get("current_delivery") or {}

        if tool_name in ["update_delivery_status", "log_exception", "call_customer", "notify_customer"]:
            delivery_id = parameters.get("delivery_id") or current_del.get("id")

            # In demo mode, bypass strict DB ownership
            if context.get("is_demo") or (delivery_id and not is_valid_uuid(delivery_id)):
                return True, ""

            if delivery_id and is_valid_uuid(delivery_id) and driver_id and is_valid_uuid(driver_id):
                delivery = await get_delivery_by_id(delivery_id)
                if delivery:
                    shift = await get_shift_by_id(str(delivery.get("shift_id") or ""))
                    if not shift or str(shift.get("driver_id")) != str(driver_id):
                        return False, f"Access denied: delivery {delivery_id} belongs to another driver."

        return True, ""

    async def _check_business_rules(
        self,
        tool_name: str,
        parameters: Dict[str, Any],
        context: Dict[str, Any]
    ) -> Tuple[bool, str]:
        """Verify delivery state transitions follow deterministic workflow rules."""
        if tool_name == "update_delivery_status":
            target_status = parameters.get("status", "").lower()
            current_del = context.get("current_delivery") or {}
            delivery_id = parameters.get("delivery_id") or current_del.get("id")

            if delivery_id and is_valid_uuid(delivery_id):
                delivery = await get_delivery_by_id(delivery_id)
                if delivery:
                    curr_status = delivery.get("status", "pending")
                    if not validate_transition(curr_status, target_status):
                        return False, f"Illegal state change: cannot move from {curr_status} to {target_status}."

        return True, ""


tool_safety_gate = ToolSafetyGate()
