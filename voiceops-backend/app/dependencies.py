import asyncio
import logging
from fastapi import Header, HTTPException, status
from typing import Optional
from app.db.client import get_supabase_client

logger = logging.getLogger(__name__)


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=detail)


async def authenticate_bearer(authorization: Optional[str]) -> dict:
    """
    Validate an `Authorization: Bearer <token>` value with Supabase and return the user as a dict.

    Shared by REST (`get_current_driver`) and the voice WebSocket upgrade, so both use the one
    scheme in docs/contracts/interface.md §4.
    """
    if not authorization:
        raise _unauthorized("Authorization header missing")

    # Extract Bearer token
    if not authorization.startswith("Bearer "):
        raise _unauthorized("Invalid authorization header format")

    token = authorization[7:]  # Remove "Bearer " prefix

    try:
        supabase = get_supabase_client()
    except Exception as e:
        # SUPABASE_URL / SUPABASE_SERVICE_KEY missing or unusable: the server's fault, not the
        # driver's, so it must not read as an expired token (the app would say "sign in again").
        logger.error("[Auth] Supabase client unavailable (%s); check SUPABASE_URL and SUPABASE_SERVICE_KEY", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Server sign-in check is not configured",
        )

    try:
        # Validate JWT with Supabase (sync client, so keep it off the event loop)
        user = await asyncio.to_thread(supabase.auth.get_user, token)
    except Exception as e:
        logger.warning("[Auth] Token rejected: %s status=%s", type(e).__name__, getattr(e, "status", None))
        raise _unauthorized("Invalid or expired token")

    if not user or not user.user:
        raise _unauthorized("Invalid or expired token")

    return user.user.model_dump()


async def get_current_driver(authorization: Optional[str] = Header(None)) -> dict:
    """Validate Supabase JWT and return driver info."""
    return await authenticate_bearer(authorization)


# ---------------------------------------------------------------------------
# Operator / dispatcher role gate
# ---------------------------------------------------------------------------

_OPERATOR_ROLES = {"operator", "dispatcher", "admin"}


async def get_current_operator(authorization: Optional[str] = Header(None)) -> dict:
    """
    Validate Supabase JWT and assert that the caller holds an operator role.

    The role is read from ``app_metadata.role`` (set server-side by Supabase or a
    management API call — drivers cannot self-assign it).  A driver token that hits
    an operator-gated endpoint receives 403 Forbidden.

    Decision rationale (handoff §2): operator identity via a Supabase role claim
    in the JWT was chosen over a separate ``operators`` table because it requires no
    extra schema and can be enforced entirely in the auth layer.
    To grant a user operator access:
        supabase.auth.admin.update_user_by_id(uid, {"app_metadata": {"role": "operator"}})
    """
    user = await authenticate_bearer(authorization)

    # app_metadata is set by Supabase admin APIs; users cannot modify it themselves.
    app_meta = user.get("app_metadata") or {}
    role = str(app_meta.get("role", "")).lower()

    if role not in _OPERATOR_ROLES:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Operator or dispatcher role required.",
        )

    return user
