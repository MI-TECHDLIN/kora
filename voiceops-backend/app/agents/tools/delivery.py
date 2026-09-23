"""
Delivery tools for VoiceOps agent — wired to live Supabase.
Tools: get_next_delivery, update_delivery_status, log_exception, get_next_order, accept_order, decline_order, get_shift_summary, end_shift
"""
import logging
from typing import Dict, Any

from app.dispatch.order_dispatch import get_order_dispatcher

logger = logging.getLogger(__name__)


DEMO_NEXT_DELIVERY = {
    "id": "mock-delivery-123",
    "recipient_name": "Amara Johnson",
    "address": "14 Broad Street, Lagos Island",
    "phone": "+2348012345678",
    "status": "pending",
    "notes": "Ring bell twice. 3rd floor.",
    "time_window": "2:00 PM - 4:00 PM",
    "latitude": 6.4541,
    "longitude": 3.3947,
    "sequence_order": 4,
}


def _delivery_result(delivery: dict) -> dict:
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
        "sequence": delivery.get("sequence_order") or delivery.get("sequence"),
    }


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
                return _delivery_result({"sequence_order": current.get("sequence"), **current})
            return {"success": True, "has_next": False, "message": "No active shift found."}

        try:
            delivery = await get_next_pending_delivery(shift_id, driver_id)
        except Exception as e:
            logger.warning(f"[Tool:get_next_delivery] Supabase unavailable; using demo stop: {e}")
            return _delivery_result(DEMO_NEXT_DELIVERY)

        if not delivery:
            return {
                "success": True,
                "has_next": False,
                "message": "All deliveries are complete for this shift. Great work!",
            }

        return _delivery_result(delivery)

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
                
                # Trigger summary generation on delivery completion
                if status == "delivered":
                    shift_id = context.get("shift_id")
                    driver_id = context.get("driver_id")
                    if shift_id and driver_id:
                        from app.intelligence.lemur_pipeline import run_shift_intelligence
                        from app.api.websocket.voice import stream_summary
                        # Trigger intelligence analysis in background
                        import asyncio
                        asyncio.create_task(_trigger_delivery_summary(shift_id, driver_id))
                
                return {
                    "success": True,
                    "delivery_id": delivery_id,
                    "status": status,
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
    Get the next order waiting for a driver from the order dispatcher's live queue:
    the order offered to this driver, else the nearest unassigned one.

    Trigger phrases: "next order in queue", "what's coming after this", "next job"
    """
    try:
        found = get_order_dispatcher().next_order_for(
            context.get("driver_id"), context.get("latitude"), context.get("longitude"))
        if not found:
            return {"success": True, "has_next": False, "message": "No new orders are waiting right now."}
        if found["offered_to_you"]:
            message = (f"Order offered to you: {found['address']}, {found['distance_km']:.1f} km away. "
                       "Accept or decline it.")
        else:
            message = (f"Next order in the queue: {found['address']}, {found['distance_km']:.1f} km away. "
                       "It is not assigned to anyone yet.")
        # sequence_order: an order has no place on a run until a driver accepts it
        return {"success": True, "has_next": True, **found, "sequence_order": None, "message": message}

    except Exception as e:
        logger.error(f"[Tool:get_next_order] {e}")
        return {"success": False, "error": str(e)}


async def accept_order(parameters: dict, context: dict) -> dict:
    """
    Accept a new order: it becomes the last pending stop on the driver's shift.
    order_id is optional and defaults to the order currently offered to the driver.

    Trigger phrases: "yes, I'll take it", "accept", "add it to my run"
    
    Prefers to check driver preferences for auto_accept_orders and max_order_distance_km.
    """
    order_id = parameters.get("order_id")
    shift_id = context.get("shift_id")
    driver_id = context.get("driver_id")
    
    try:
        if not driver_id or not shift_id:
            logger.warning(
                "[Tool:accept_order] accept_failed order_id=%s shift_id=%s "
                "reason=missing_active_shift",
                order_id or "-", shift_id or "-",
            )
            return {"success": False, "error": "No active shift to add the order to."}
        
        # Check driver preferences
        from app.services.preference_service import preference_service
        preferences = await preference_service.get_preferences(driver_id)
        
        # Resolve any preference conflicts
        from app.services.preference_models import PreferenceConflictResolver
        preferences = PreferenceConflictResolver.resolve_all_conflicts(preferences)
        
        # If auto_decline_orders is set, reject the acceptance
        if preferences.get("auto_decline_orders") == "true":
            logger.info(
                "[Tool:accept_order] accept_rejected_by_preference driver_id=%s "
                "preference=auto_decline_orders",
                driver_id,
            )
            return {
                "success": False,
                "error": "Cannot accept order: auto-decline preference is enabled."
            }
        
        # Get enhanced preferences for advanced checks
        enhanced_prefs = await preference_service.get_enhanced_preferences(driver_id)
        
        # Get order details for comprehensive checking
        dispatcher = get_order_dispatcher()
        order = await dispatcher.get_order(order_id) if order_id else context.get("offered_order")
        
        if order:
            # Check geographic zone preferences
            from app.utils.geo_preferences import is_order_acceptable_by_location
            order_lat = order.get("pickup_latitude") or order.get("latitude")
            order_lon = order.get("pickup_longitude") or order.get("longitude")
            driver_lat = context.get("latitude") or context.get("current_latitude")
            driver_lon = context.get("longitude") or context.get("current_longitude")
            
            if order_lat and order_lon and driver_lat and driver_lon:
                location_acceptable, location_reason = is_order_acceptable_by_location(
                    order_lat, order_lon, driver_lat, driver_lon,
                    max_distance_km=preferences.get("max_order_distance_km"),
                    pickup_radius_km=enhanced_prefs.pickup_radius_km,
                    zones=enhanced_prefs.geographic_zones
                )
                
                if not location_acceptable:
                    logger.info(
                        "[Tool:accept_order] accept_rejected_by_location driver_id=%s reason=%s",
                        driver_id, location_reason,
                    )
                    return {
                        "success": False,
                        "error": f"Cannot accept order: {location_reason}"
                    }
            
            # Check order type preferences
            from app.utils.order_type_preferences import is_order_type_accepted
            order_category = order.get("category", "delivery")
            order_weight = order.get("weight_kg")
            order_dimensions = order.get("dimensions")
            order_value = order.get("value")
            
            type_acceptable, type_reason = is_order_type_accepted(
                order_category, order_weight, order_dimensions, order_value,
                enhanced_prefs.order_type_prefs
            )
            
            if not type_acceptable:
                logger.info(
                    "[Tool:accept_order] accept_rejected_by_type driver_id=%s reason=%s",
                    driver_id, type_reason,
                )
                return {
                    "success": False,
                    "error": f"Cannot accept order: {type_reason}"
                }
            
            # Check time-based preferences
            from app.utils.time_preferences import should_accept_order_by_time
            from datetime import datetime
            time_acceptable, time_reason = should_accept_order_by_time(
                datetime.now(), enhanced_prefs.time_based_prefs
            )
            
            if not time_acceptable:
                logger.info(
                    "[Tool:accept_order] accept_rejected_by_time driver_id=%s reason=%s",
                    driver_id, time_reason,
                )
                return {
                    "success": False,
                    "error": f"Cannot accept order: {time_reason}"
                }
        
        # Legacy max_order_distance_km check (fallback)
        max_distance = preferences.get("max_order_distance_km")
        if max_distance and order and order.get("distance_km"):
            try:
                max_distance_km = float(max_distance)
                if order["distance_km"] > max_distance_km:
                    logger.info(
                        "[Tool:accept_order] accept_rejected_by_distance driver_id=%s "
                        "order_distance=%s max_allowed=%s",
                        driver_id, order["distance_km"], max_distance_km,
                    )
                    return {
                        "success": False,
                        "error": f"Order distance ({order['distance_km']:.1f} km) exceeds your preference of {max_distance_km} km."
                    }
            except (ValueError, TypeError):
                logger.warning(f"[Tool:accept_order] Invalid max_order_distance_km value: {max_distance}")
        
        result = await get_order_dispatcher().accept(driver_id, shift_id, order_id)
        if not result.get("success"):
            logger.warning(
                "[Tool:accept_order] accept_failed order_id=%s shift_id=%s "
                "reason=dispatcher_rejected detail=%r",
                order_id or "-", shift_id, result.get("error") or "unknown",
            )
        return result

    except Exception as e:
        logger.error(
            "[Tool:accept_order] accept_failed order_id=%s shift_id=%s "
            "reason=unexpected_exception error_type=%s",
            order_id or "-", shift_id or "-", type(e).__name__,
        )
        return {"success": False, "error": str(e)}


async def decline_order(parameters: dict, context: dict) -> dict:
    """
    Decline the order offered to the driver: it goes to the next-nearest free driver.
    order_id is optional and defaults to the order currently offered to the driver.

    Trigger phrases: "no", "pass", "decline it", "I can't take it"
    
    Checks driver preferences for auto_accept_orders - if enabled, decline is rejected.
    """
    driver_id = context.get("driver_id")
    
    try:
        if not driver_id:
            return {"success": False, "error": "No driver on this session."}
        
        # Check driver preferences
        from app.services.preference_service import preference_service
        preferences = await preference_service.get_preferences(driver_id)
        
        # If auto_accept_orders is set, reject the decline
        if preferences.get("auto_accept_orders") == "true":
            logger.info(
                "[Tool:decline_order] decline_rejected_by_preference driver_id=%s "
                "preference=auto_accept_orders",
                driver_id,
            )
            return {
                "success": False,
                "error": "Cannot decline order: auto-accept preference is enabled."
            }
        
        return await get_order_dispatcher().decline(
            driver_id, parameters.get("order_id"), parameters.get("reason"),
            shift_id=context.get("shift_id"))

    except Exception as e:
        logger.error(f"[Tool:decline_order] {e}")
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


async def end_shift(parameters: dict, context: dict) -> dict:
    """
    End the driver's current shift: marks it completed, persists shift stats and timing,
    and triggers the post-shift LeMUR intelligence report and n8n notification. This is
    the only driver-reachable trigger for `POST /v1/shift/{shift_id}/end` today - distinct
    from `end_conversation`, which only closes the voice socket and has no DB effect.

    Trigger phrases: "end my shift", "I'm done for the day", "clock out", "that's it for today"
    """
    try:
        shift_id = context.get("shift_id")
        driver_id = context.get("driver_id")
        if not shift_id or not driver_id:
            return {"success": False, "error": "No active shift to end."}

        from app.api.routes.shift import end_shift_core, run_shift_intelligence_and_stream

        driver_name = context.get("driver_name") or "Driver"
        result = await end_shift_core(shift_id, driver_id, driver_name)

        import asyncio
        asyncio.create_task(run_shift_intelligence_and_stream(shift_id, driver_id))

        return {
            "success": True,
            "shift_id": shift_id,
            "status": result.get("status", "completed"),
            "shift_duration_min": result.get("shift_duration_min", 0),
            "message": "Shift ended. I'm putting together your summary now.",
        }

    except Exception as e:
        logger.error(f"[Tool:end_shift] {e}")
        return {"success": False, "error": str(e)}


async def _trigger_delivery_summary(shift_id: str, driver_id: str):
    """
    Background task to trigger intelligence analysis after delivery completion.
    """
    try:
        from app.intelligence.lemur_pipeline import run_shift_intelligence
        from app.api.websocket.voice import stream_summary
        
        logger.info(f"[Delivery Summary] Triggering intelligence analysis for shift {shift_id}")
        result = await run_shift_intelligence(shift_id, driver_id)
        
        # Stream summary to open voice socket if available
        summary = result.get("analysis", {}).get("executive_summary", "")
        if summary:
            await stream_summary(shift_id, summary)
            
        logger.info(f"[Delivery Summary] Intelligence analysis completed for shift {shift_id}")
    except Exception as e:
        logger.error(f"[Delivery Summary] Failed to trigger intelligence analysis: {e}")
