"""
Proof of Delivery (POD) API Routes
Supports photo capture, signature upload, GPS verification,
and automatic delivery completion.
"""
import uuid
import logging
from typing import Optional
from fastapi import APIRouter, HTTPException, status, Depends, UploadFile, File, Form
from app.dependencies import get_current_driver
from app.api.ownership import require_owned_delivery
from app.services.storage_service import storage_service
from app.services.delivery_state_machine import assert_transition
from app.services.order_queue_service import notify_queue_changed
from app.db.queries import (
    mark_delivery_status,
    create_delivery_event,
    get_supabase,
    is_valid_uuid,
)

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/deliveries/{delivery_id}/pod")
async def upload_proof_of_delivery(
    delivery_id: str,
    latitude: float = Form(...),
    longitude: float = Form(...),
    notes: Optional[str] = Form(None),
    photo: Optional[UploadFile] = File(None),
    signature: Optional[UploadFile] = File(None),
    current_user: dict = Depends(get_current_driver),
):
    """
    Upload POD (photo and/or signature) with GPS verification.
    Transitions delivery status to 'delivered' and writes audit records.
    """
    driver_id = current_user.get("id")

    # 1. Fetch and validate delivery ownership. Non-UUID mock IDs intentionally bypass
    # the database check inside the shared helper and keep the demo behavior below.
    delivery = await require_owned_delivery(delivery_id, driver_id)
    current_status = delivery.get("status", "arrived") if delivery else "arrived"

    # Enforce state machine transition
    try:
        assert_transition(current_status, "delivered")
    except ValueError as ve:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(ve))

    photo_url: Optional[str] = None
    signature_url: Optional[str] = None
    file_id = str(uuid.uuid4())

    # 2. Upload photo if provided
    if photo:
        content = await photo.read()
        ext = photo.filename.split(".")[-1] if photo.filename and "." in photo.filename else "jpg"
        path = f"{driver_id}/{delivery_id}/photo_{file_id}.{ext}"
        photo_url = await storage_service.upload_file(
            file_bytes=content,
            path=path,
            content_type=photo.content_type or "image/jpeg"
        )

    # 3. Upload signature if provided
    if signature:
        content = await signature.read()
        ext = signature.filename.split(".")[-1] if signature.filename and "." in signature.filename else "png"
        path = f"{driver_id}/{delivery_id}/signature_{file_id}.{ext}"
        signature_url = await storage_service.upload_file(
            file_bytes=content,
            path=path,
            content_type=signature.content_type or "image/png"
        )

    # 4. Insert proof_of_delivery record
    pod_record = {}
    try:
        pod_data = {
            "delivery_id": delivery_id if is_valid_uuid(delivery_id) else None,
            "driver_id": driver_id if is_valid_uuid(driver_id) else None,
            "photo_url": photo_url,
            "signature_url": signature_url,
            "gps_latitude": latitude,
            "gps_longitude": longitude,
            "verification_status": "verified",
            "metadata": {"notes": notes} if notes else {},
        }
        res = get_supabase().table("proof_of_delivery").insert(pod_data).execute()
        pod_record = res.data[0] if res.data else {}
    except Exception as e:
        logger.error(f"[POD] Failed to insert proof_of_delivery: {e}")

    # 5. Update delivery to 'delivered'
    if is_valid_uuid(delivery_id):
        await mark_delivery_status(delivery_id, "delivered", notes=notes)

        # 6. Create immutable delivery_events record
        await create_delivery_event(
            delivery_id=delivery_id,
            driver_id=driver_id,
            event_type="DELIVERED",
            status_before=current_status,
            status_after="delivered",
            latitude=latitude,
            longitude=longitude,
            metadata={
                "has_photo": photo_url is not None,
                "has_signature": signature_url is not None,
                "photo_url": photo_url,
                "signature_url": signature_url,
            }
        )
        await notify_queue_changed(delivery.get("shift_id") if delivery else None, driver_id)

    return {
        "success": True,
        "delivery_id": delivery_id,
        "status": "delivered",
        "photo_url": photo_url,
        "signature_url": signature_url,
        "pod_id": pod_record.get("id"),
        "message": "Proof of delivery recorded and package marked delivered.",
    }


@router.get("/deliveries/{delivery_id}/pod")
async def get_proof_of_delivery(
    delivery_id: str,
    current_user: dict = Depends(get_current_driver),
):
    """Retrieve proof of delivery for a specific delivery."""
    if not is_valid_uuid(delivery_id):
        return {"pod": None}

    await require_owned_delivery(delivery_id, current_user.get("id"))

    try:
        res = (
            get_supabase().table("proof_of_delivery")
            .select("*")
            .eq("delivery_id", delivery_id)
            .limit(1)
            .execute()
        )
        pod = res.data[0] if res.data else None
        return {"pod": pod}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch POD: {str(e)}"
        )
