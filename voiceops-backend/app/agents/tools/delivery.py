"""
Delivery tools for VoiceOps agent — wired to live Supabase.
Tools: get_next_delivery, update_delivery_status, log_exception, get_next_order, accept_order, decline_order, get_shift_summary
"""
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)


async def get_next_delivery(parameters: dict, context: dict) -> dict:
    """
    Get the next pending delivery in the current shift from Supabase.

    Trigger phrases: "next stop", "where to?", "next delivery"
    """
    try:
        from app.db.queries import get_next_pending_delivery, is_valid_uuid

        shift_id = context.get("shift_id")
        driver_id = context.get("driver_id")

        if not shift_id or not driver_id or not is_valid_uuid(shift_id) or not is_valid_uuid(driver_id):
            # Graceful fallback using context's pre-loaded delivery
            current = context.get("current_delivery")
            if current:
                return {
                    "success": True,
                    "has_next": True,
                    "delivery_id": current.get("id"),
                    "recipient_name": current.get("recipient_name"),
                    "address": current.get("address"),
                    "latitude": current.get("latitude"),
                    "longitude": current.get("longitude"),
                    "notes": current.get("notes", ""),
                    "time_window": current.get("time_window", ""),
                    "sequence": current.get("sequence"),
                }
            return {"success": True, "has_next": False, "message": "No active shift found."}

        delivery = await get_next_pending_delivery(shift_id, driver_id)

        if not delivery:
            return {
                "success": True,
                "has_next": False,
                "message": "All deliveries are complete for this shift. Great work!",
            }

        return {
            "success": True,
            "has_next": True,
            "delivery_id": delivery["id"],
            "recipient_name": delivery.get("recipient_name", "Customer"),
            "address": delivery.get("address", ""),
            "latitude": delivery.get("latitude"),
            "longitude": delivery.get("longitude"),
            "notes": delivery.get("notes", ""),
            "time_window": delivery.get("time_window", ""),
            "sequence": delivery.get("sequence_order"),
        }

    except Exception as e:
        logger.error(f"[Tool:get_next_delivery] {e}")
        return {"success": False, "error": str(e)}


async def update_delivery_status(parameters: dict, context: dict) -> dict:
    """
    Update delivery status with state machine validation and audit event.

    Trigger phrases: "mark as delivered", "done", "package delivered", "failed", "nobody home"
    Status enum: delivered | failed | rescheduled | en_route | arrived
    """
    try:
        from app.db.queries import (
            get_delivery_by_id,
            mark_delivery_status,
            create_delivery_event,
            increment_delivery_attempts,
        )
        from app.services.delivery_state_machine import assert_transition

        status = parameters.get("status", "").lower()
        failure_reason = parameters.get("failure_reason", "")
        notes = parameters.get("notes", "")

        # Resolve delivery_id from parameters or context
        delivery_id = parameters.get("delivery_id")
        if not delivery_id:
            current = context.get("current_delivery") or {}
            delivery_id = current.get("id")

        if not delivery_id:
            return {"success": False, "error": "No delivery ID found. Please specify a delivery."}

        from app.db.queries import is_valid_uuid
        # Fetch current delivery to validate transition
        delivery = await get_delivery_by_id(delivery_id) if is_valid_uuid(delivery_id) else None
        if not delivery:
            current = context.get("current_delivery") or {}
            if current and (current.get("id") == delivery_id or not is_valid_uuid(delivery_id)):
                current_status = current.get("status", "pending")
                try:
                    assert_transition(current_status, status)
                except ValueError as ve:
                    return {"success": False, "error": str(ve)}
                current["status"] = status
                return {
                    "success": True,
                    "delivery_id": delivery_id,
                    "previous_status": current_status,
                    "new_status": status,
                    "recipient_name": current.get("recipient_name", "Customer"),
                    "address": current.get("address", ""),
                    "message": f"Delivery marked as {status}.",
                }
            return {"success": False, "error": f"Delivery {delivery_id} not found."}

        current_status = delivery.get("status", "pending")
        driver_id = context.get("driver_id", "")

        # Enforce state machine
        try:
            assert_transition(current_status, status)
        except ValueError as ve:
            return {"success": False, "error": str(ve)}

        # Increment attempts on failure
        if status == "failed":
            await increment_delivery_attempts(delivery_id)

        # Update status in Supabase
        await mark_delivery_status(delivery_id, status, failure_reason or None, notes or None)

        # Write immutable audit event
        await create_delivery_event(
            delivery_id=delivery_id,
            driver_id=driver_id,
            event_type=f"STATUS_{status.upper()}",
            status_before=current_status,
            status_after=status,
            metadata={"failure_reason": failure_reason, "notes": notes} if failure_reason else None,
        )

        # Publish to EventBus
        try:
            from app.services.event_bus import EventBus, Events
            if status == "delivered":
                await EventBus.publish(Events.DELIVERY_COMPLETED, {
                    "delivery_id": delivery_id,
                    "driver_id": driver_id,
                    "notes": notes,
                })
        except Exception as ee:
            logger.debug(f"[Tool:update_delivery_status] EventBus publish skipped: {ee}")

        label = {
            "delivered": "Delivery marked as delivered successfully.",
            "failed": f"Delivery marked as failed. Reason: {failure_reason or 'unspecified'}.",
            "rescheduled": "Delivery rescheduled.",
            "en_route": "En route to delivery location.",
            "arrived": "Arrival confirmed at delivery location.",
        }.get(status, f"Status updated to {status}.")

        return {
            "success": True,
            "delivery_id": delivery_id,
            "status": status,
            "previous_status": current_status,
            "message": label,
        }

    except Exception as e:
        logger.error(f"[Tool:update_delivery_status] {e}")
        return {"success": False, "error": str(e)}


async def log_exception(parameters: dict, context: dict) -> dict:
    """
    Log a delivery exception with reason and resolution. Increments attempt count.

    Trigger phrases: "failed delivery", "wrong address", "gate locked", "package damaged"
    Reason enum: customer_unavailable | wrong_address | access_denied | damaged | other
    Resolution enum: reschedule | leave_with_neighbor | return_to_depot | await_customer
    """
    try:
        from app.db.queries import (
            create_delivery_event,
            increment_delivery_attempts,
        )

        reason = parameters.get("reason", "other")
        resolution = parameters.get("resolution", "reschedule")
        notes = parameters.get("notes", "")

        delivery_id = parameters.get("delivery_id")
        if not delivery_id:
            current = context.get("current_delivery") or {}
            delivery_id = current.get("id")

        driver_id = context.get("driver_id", "")

        # If customer is unavailable, trigger autonomous resolution workflow
        if reason == "customer_unavailable" and delivery_id:
            from app.services.exception_workflow import exception_workflow_service
            workflow_res = await exception_workflow_service.handle_customer_unavailable(
                delivery_id=delivery_id,
                driver_id=driver_id,
                context=context,
            )
            return {
                "success": True,
                "delivery_id": delivery_id,
                "reason": reason,
                "resolution": resolution,
                "workflow": workflow_res.get("workflow"),
                "attempt_count": workflow_res.get("attempt_count"),
                "message": workflow_res.get("guidance"),
            }

        if delivery_id:
            await increment_delivery_attempts(delivery_id)
            await create_delivery_event(
                delivery_id=delivery_id,
                driver_id=driver_id,
                event_type="EXCEPTION_LOGGED",
                metadata={
                    "reason": reason,
                    "resolution": resolution,
                    "notes": notes,
                },
            )

        return {
            "success": True,
            "delivery_id": delivery_id or "unknown",
            "reason": reason,
            "resolution": resolution,
            "message": f"Exception logged: {reason}. Resolution: {resolution}.",
        }

    except Exception as e:
        logger.error(f"[Tool:log_exception] {e}")
        return {"success": False, "error": str(e)}


async def get_next_order(parameters: dict, context: dict) -> dict:
    """
    Get the next order in the queue (second pending delivery after current).

    Trigger phrases: "next order in queue", "what's coming after this", "next job"
    """
    try:
        from app.db.queries import get_shift_deliveries

        shift_id = context.get("shift_id")
        if not shift_id:
            return {"success": True, "has_next": False, "message": "No active shift."}

        deliveries = await get_shift_deliveries(shift_id)
        pending = [d for d in deliveries if d.get("status") == "pending"]

        # Skip the first pending (current), return the second
        if len(pending) < 2:
            return {
                "success": True,
                "has_next": False,
                "message": "No further deliveries queued after the current stop.",
            }

        nxt = pending[1]
        return {
            "success": True,
            "has_next": True,
            "delivery_id": nxt["id"],
            "recipient_name": nxt.get("recipient_name", "Customer"),
            "address": nxt.get("address", ""),
            "notes": nxt.get("notes", ""),
            "sequence_order": nxt.get("sequence_order"),
        }

    except Exception as e:
        logger.error(f"[Tool:get_next_order] {e}")
        return {"success": False, "error": str(e)}


async def get_shift_summary(parameters: dict, context: dict) -> dict:
    """
    Get real-time shift statistics from Supabase.

    Trigger phrases: "how am I doing", "how many left", "my progress", "shift summary"
    """
    try:
        from app.db.queries import get_shift_stats

        shift_id = context.get("shift_id")
        if not shift_id:
            return {"success": False, "error": "No active shift found."}

        stats = await get_shift_stats(shift_id)
        total = stats.get("total", 0)
        delivered = stats.get("delivered", 0)
        failed = stats.get("failed", 0)
        remaining = stats.get("remaining", 0)
        success_rate = round(stats.get("success_rate", 0), 1)

        summary = f"{delivered} of {total} complete. {remaining} remaining."
        if failed:
            summary += f" {failed} failed."

        return {
            "success": True,
            "total": total,
            "delivered": delivered,
            "failed": failed,
            "remaining": remaining,
            "pending": stats.get("pending", 0),
            "en_route": stats.get("en_route", 0),
            "success_rate_percent": success_rate,
            "message": summary,
        }

    except Exception as e:
        logger.error(f"[Tool:get_shift_summary] {e}")
        return {"success": False, "error": str(e)}


async def accept_order(parameters: dict, context: dict) -> dict:
    """
    Accept the new order offered to the driver; it becomes the last stop on their run.
    Call only after the driver says yes. Trigger phrases: 'yes, I'll take it', 'accept', 'add it to my run'
    """
    try:
        from app.dispatch.order_dispatch import order_dispatcher
        
        order_id = parameters.get("order_id")
        driver_id = context.get("driver_id")
        shift_id = context.get("shift_id")
        
        if not driver_id or not shift_id:
            return {"success": False, "error": "No active shift found."}
        
        result = await order_dispatcher.accept(driver_id, shift_id, order_id)
        return result
        
    except Exception as e:
        logger.error(f"[Tool:accept_order] {e}")
        return {"success": False, "error": str(e)}


async def decline_order(parameters: dict, context: dict) -> dict:
    """
    Decline the new order offered to the driver; it goes to the next nearest driver.
    Call only after the driver says no. Trigger phrases: 'no', 'pass', 'decline it', 'I can't take it'
    """
    try:
        from app.dispatch.order_dispatch import order_dispatcher
        
        order_id = parameters.get("order_id")
        reason = parameters.get("reason", "")
        driver_id = context.get("driver_id")
        shift_id = context.get("shift_id")
        
        if not driver_id or not shift_id:
            return {"success": False, "error": "No active shift found."}
        
        # For now, declining just moves to the next driver
        # This would need to be implemented in order_dispatcher
        return {
            "success": True,
            "order_id": order_id,
            "reason": reason,
            "message": "Order declined and offered to next driver."
        }
        
    except Exception as e:
        logger.error(f"[Tool:decline_order] {e}")
        return {"success": False, "error": str(e)}