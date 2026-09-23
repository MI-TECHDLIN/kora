"""
Autonomous Exception Workflow Service
Executes multi-step resolution workflows when exceptions occur
(e.g., customer unavailable, access denied, damaged package).
"""
import logging
from typing import Dict, Any, Optional
from app.integrations.twilio_client import make_call, send_sms
from app.integrations.n8n_client import trigger_dispatcher_alert_background
from app.db.queries import (
    get_delivery_by_id,
    increment_delivery_attempts,
    create_delivery_event,
    get_supabase,
    is_valid_uuid,
)

logger = logging.getLogger(__name__)


class ExceptionWorkflowService:
    async def handle_customer_unavailable(
        self,
        delivery_id: str,
        driver_id: str,
        context: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Executes autonomous customer unavailable protocol:
        1. Call customer via Twilio
        2. Send follow-up SMS
        3. Increment attempt count
        4. Log audit delivery event
        5. Escalate to dispatcher if repeated
        """
        ctx = context or {}
        driver_name = ctx.get("driver_name", "Driver")
        shift_id = ctx.get("shift_id", "")

        delivery = await get_delivery_by_id(delivery_id) if is_valid_uuid(delivery_id) else None
        if not delivery:
            delivery = ctx.get("current_delivery") or {}

        phone = delivery.get("phone") or delivery.get("customer_phone")
        name = delivery.get("recipient_name") or "Customer"
        address = delivery.get("address") or "delivery address"

        workflow_steps = []

        # 1. Attempt outbound automated call
        call_success = False
        if phone:
            call_res = await make_call(
                to_phone=phone,
                message=f"Hello {name}, your Kora delivery driver is waiting outside {address}. Please come to receive your delivery.",
                delivery_id=delivery_id,
                recipient_name=name,
            )
            call_success = call_res.get("success", False)
            workflow_steps.append({"step": "outbound_call", "success": call_success})

        # 2. Send follow-up SMS
        sms_success = False
        if phone:
            sms_text = f"Hi {name}, your driver is at {address} but unable to reach you. Please contact support or come outside."
            sms_res = await send_sms(to_phone=phone, message=sms_text, customer_name=name)
            sms_success = sms_res.get("success", False)
            workflow_steps.append({"step": "sms_fallback", "success": sms_success})

        # 3. Increment attempt count
        attempts = 1
        if is_valid_uuid(delivery_id):
            updated_del = await increment_delivery_attempts(delivery_id)
            attempts = updated_del.get("attempt_count", 1)

        # 4. Log delivery event
        if is_valid_uuid(delivery_id):
            await create_delivery_event(
                delivery_id=delivery_id,
                driver_id=driver_id,
                event_type="EXCEPTION_CUSTOMER_UNAVAILABLE",
                metadata={
                    "attempt_count": attempts,
                    "call_dispatched": call_success,
                    "sms_dispatched": sms_success,
                }
            )

        # 5. Escalate to dispatcher
        trigger_dispatcher_alert_background(
            driver_id=str(driver_id),
            driver_name=str(driver_name),
            alert_type="customer_unavailable",
            message=f"Driver {driver_name} cannot reach customer {name} at {address} (Attempt #{attempts}).",
            severity="urgent" if attempts >= 2 else "normal",
            location=str(address),
            shift_id=str(shift_id),
        )
        workflow_steps.append({"step": "dispatcher_escalation", "success": True})

        guidance = (
            f"I called and sent an SMS to {name}. I also updated dispatch. "
            f"Please wait 2 minutes; if they don't show up, you can move to your next stop."
        )

        return {
            "success": True,
            "workflow": "customer_unavailable",
            "attempt_count": attempts,
            "steps": workflow_steps,
            "guidance": guidance,
        }


exception_workflow_service = ExceptionWorkflowService()
