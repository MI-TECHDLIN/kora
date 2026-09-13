"""
POST /v1/logistics/orders: the Order Intake API (docs/contracts/interface.md §2).

A logistics platform pushes each new order here as an `OrderCreatedEvent`, and VoiceOps offers
it to the nearest driver (app/dispatch/order_dispatch.py). The MockAdapter's feed produces the
same payload internally.

This is server to server, so there is no driver JWT. The platform signs the raw request body
with the shared secret LOGISTICS_WEBHOOK_SECRET and sends
`X-VoiceOps-Signature: sha256=<hex HMAC-SHA256>`, the usual webhook-signing scheme. Without a
configured secret the endpoint is off (503), so it is never an open write path.
"""
import hashlib
import hmac
import json
from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Request, status
from pydantic import ValidationError

from app.config import settings
from app.dispatch.order_dispatch import DispatchUnavailable, get_order_dispatcher
from app.integrations.logistics import IncomingOrder
from app.models.schemas import OrderCreatedEvent

router = APIRouter()

SIGNATURE_PREFIX = "sha256="


def sign_body(body: bytes, secret: str) -> str:
    """The `X-VoiceOps-Signature` value for a request body."""
    return SIGNATURE_PREFIX + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


@router.post("/orders", status_code=status.HTTP_202_ACCEPTED)
async def receive_order(request: Request, x_voiceops_signature: Optional[str] = Header(None)):
    """Take a new order from a logistics platform and start offering it to drivers."""
    secret = settings.logistics_webhook_secret
    if not secret:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail="Order intake is not configured")

    body = await request.body()
    if not x_voiceops_signature or not hmac.compare_digest(x_voiceops_signature, sign_body(body, secret)):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid signature")

    try:
        event = OrderCreatedEvent.model_validate_json(body)
    except ValidationError as e:
        raise HTTPException(status_code=422, detail=json.loads(e.json(include_url=False)))

    try:
        result = await get_order_dispatcher().ingest(IncomingOrder.from_event(event))
    except DispatchUnavailable as e:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e))

    return {
        "order_id": result["order_id"],
        "external_id": event.external_id,
        "status": result["status"],
        "duplicate": result["duplicate"],
    }
