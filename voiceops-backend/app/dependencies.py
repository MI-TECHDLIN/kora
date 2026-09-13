import asyncio
from fastapi import Header, HTTPException, status
from typing import Optional
from app.db.client import get_supabase_client


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
        # Validate JWT with Supabase (sync client, so keep it off the event loop)
        supabase = get_supabase_client()
        user = await asyncio.to_thread(supabase.auth.get_user, token)
    except Exception:
        raise _unauthorized("Invalid or expired token")

    if not user or not user.user:
        raise _unauthorized("Invalid or expired token")

    return user.user.model_dump()


async def get_current_driver(authorization: Optional[str] = Header(None)) -> dict:
    """Validate Supabase JWT and return driver info."""
    return await authenticate_bearer(authorization)
