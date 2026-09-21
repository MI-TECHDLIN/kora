"""
Customer Notification Policy Service
Implements automated customer communication rules based on ETA thresholds,
preventing spam while ensuring timely customer notifications.
"""
import logging
from typing import Optional
from app.integrations.twilio_client import send_sms
from app.db.queries import get_delivery_by_id, get_supabase, is_valid_uuid

logger = logging.getLogger(__name__)


class NotificationPolicyService:
    PROXIMITY_THRESHOLD_MINUTES: int = 15

    async def should_notify_customer(
        self,
        delivery_id: str,
        eta_minutes: int,
    ) -> bool:
        """
        Evaluate notification policy:
        1. ETA must be <= 15 minutes.
        2. Delivery must not already have a recent SMS sent.
        """
        if not is_valid_uuid(delivery_id):
            return False

        if eta_minutes > self.PROXIMITY_THRESHOLD_MINUTES:
            return False

        # Check if customer has already received an SMS for this delivery
        try:
            res = (
                get_supabase().table("customer_interactions")
                .select("id")
                .eq("delivery_id", delivery_id)
                .eq("channel", "sms")
                .limit(1)
                .execute()
            )
            if res.data and len(res.data) > 0:
                # Already notified
                return False
        except Exception as e:
            logger.warning(f"[NotificationPolicy] Error checking interactions: {e}")

        return True

    async def send_eta_notification(
        self,
        delivery_id: str,
        eta_minutes: int,
    ) -> bool:
        """
        Sends automated proximity SMS via Twilio and logs customer interaction.
        """
        if not is_valid_uuid(delivery_id):
            return False

        delivery = await get_delivery_by_id(delivery_id)
        if not delivery:
            return False

        phone = delivery.get("phone") or delivery.get("customer_phone")
        name = delivery.get("recipient_name") or "Customer"

        if not phone:
            logger.warning(f"[NotificationPolicy] Delivery {delivery_id} has no phone on file.")
            return False

        message = (
            f"Hi {name}, your Kora driver is approximately {eta_minutes} minutes away. "
            f"Please be ready to receive your package at {delivery.get('address', 'your address')}."
        )

        try:
            result = await send_sms(to_phone=phone, message=message, customer_name=name)
            success = result.get("success", False)

            # Record customer interaction
            get_supabase().table("customer_interactions").insert({
                "delivery_id": delivery_id,
                "channel": "sms",
                "direction": "outbound",
                "sender_type": "automated_system",
                "content": message,
                "status": "delivered" if success else "failed",
                "external_id": result.get("message_sid"),
            }).execute()

            logger.info(f"[NotificationPolicy] Proximity SMS dispatched to {name} ({phone})")
            return success
        except Exception as e:
            logger.error(f"[NotificationPolicy] Failed to send automated SMS: {e}")
            return False


notification_policy_service = NotificationPolicyService()
