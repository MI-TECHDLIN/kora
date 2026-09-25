"""
Why the voice path can or cannot start, without ever exposing a setting's value.

Two users:
  * the relay (`app/api/websocket/voice.py`) classifies a failed AssemblyAI connect into an
    `error` event code plus a value-free `reason` for the log, and
  * `GET /health/ready` reports which settings the voice path needs are present and whether the
    server can really open the upstream session and reach the database.

Everything returned or logged here is a boolean or a token from a fixed vocabulary
(`assemblyai_key_rejected`, `timeout`, an exception class name, ...). Never put a setting value,
a token, or an upstream message body in any of it.
"""
import asyncio
import json
import logging
import time
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple

import websockets

from app.config import settings

logger = logging.getLogger(__name__)

UPSTREAM_CONNECT_TIMEOUT = 10.0  # connect + session.update → session.ready (relay)
PROBE_TIMEOUT = 8.0              # the whole readiness probe of the upstream session
DB_PROBE_TIMEOUT = 4.0
READY_CACHE_SECONDS = 30.0       # bounds how often the probes (one short upstream session) run

NOT_CONFIGURED_MESSAGE = "The voice service isn't set up on the server yet."


def upstream_headers() -> Dict[str, str]:
    return {"Authorization": f"Bearer {settings.assemblyai_api_key}"}


async def connect_upstream():
    """Open the AssemblyAI Voice Agent WebSocket. Raises what `websockets` raises; callers classify."""
    if not settings.assemblyai_api_key:
        raise UpstreamNotConfigured("assemblyai_api_key_missing")
    return await websockets.connect(
        settings.assemblyai_voice_agent_url,
        additional_headers=upstream_headers(),
        open_timeout=UPSTREAM_CONNECT_TIMEOUT,
    )


class UpstreamNotConfigured(Exception):
    """A setting the voice path needs is missing. `reason` is a fixed token, never a value."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def classify_upstream_failure(exc: BaseException) -> Tuple[str, str, str]:
    """
    `(error code, log reason, message for the app)` for a failed upstream connect.

    Codes are the `error.code` vocabulary in docs/contracts/interface.md §1.
    """
    if isinstance(exc, UpstreamNotConfigured):
        return "voice_not_configured", exc.reason, NOT_CONFIGURED_MESSAGE
    if isinstance(exc, websockets.exceptions.InvalidStatus):
        status = exc.response.status_code
        if status in (401, 403):
            return "voice_not_configured", "assemblyai_key_rejected", NOT_CONFIGURED_MESSAGE
        return "upstream_unavailable", f"assemblyai_http_{status}", "The voice service is unavailable."
    if isinstance(exc, (websockets.exceptions.InvalidURI, websockets.exceptions.InvalidHandshake)):
        return "upstream_unavailable", f"assemblyai_handshake_{type(exc).__name__}", "The voice service is unavailable."
    if isinstance(exc, asyncio.TimeoutError):
        return "upstream_timeout", "assemblyai_connect_timeout", "The voice service did not respond."
    if isinstance(exc, OSError):
        return "upstream_unavailable", f"assemblyai_unreachable_{type(exc).__name__}", "The voice service is unavailable."
    return "upstream_unavailable", f"assemblyai_connect_error_{type(exc).__name__}", "The voice service is unavailable."


# ------------------------------------------------------------------------------ readiness


def config_report() -> Dict[str, Any]:
    """Presence of each setting the voice path reads. Booleans only."""
    default_url = type(settings).model_fields["assemblyai_voice_agent_url"].default
    return {
        "required": {
            # Upstream voice session (STT + LLM + TTS)
            "ASSEMBLYAI_API_KEY": bool(settings.assemblyai_api_key),
            # Driver token check, shift start, shift lookup: all go through the Supabase service client
            "SUPABASE_URL": bool(settings.supabase_url),
            "SUPABASE_SERVICE_KEY": bool(settings.supabase_service_key),
        },
        "optional": {
            # Unset: the relay sends the inline prompt and tools instead of a stored agent
            "ASSEMBLYAI_AGENT_ID": bool(settings.assemblyai_agent_id),
            "TOMTOM_API_KEY": bool(settings.tomtom_api_key),
            "ENVIRONMENT_is_production": settings.environment.lower() == "production",
            "ASSEMBLYAI_VOICE_AGENT_URL_is_default": settings.assemblyai_voice_agent_url == default_url,
            "ASSEMBLYAI_VOICE_AGENT_URL_is_wss": settings.assemblyai_voice_agent_url.startswith("wss://"),
        },
    }


async def _probe_database() -> Dict[str, Any]:
    if not settings.supabase_url or not settings.supabase_service_key:
        return {"ok": False, "reason": "not_configured"}
    try:
        from app.db.client import get_supabase_client

        def query():
            return get_supabase_client().table("shifts").select("id").limit(1).execute()

        await asyncio.wait_for(asyncio.to_thread(query), DB_PROBE_TIMEOUT)
        return {"ok": True}
    except asyncio.TimeoutError:
        return {"ok": False, "reason": "timeout"}
    except Exception as e:
        result: Dict[str, Any] = {"ok": False, "reason": f"query_failed_{type(e).__name__}"}
        code = getattr(e, "code", None)  # PostgREST / Postgres error code (e.g. 42P01), not a value
        if isinstance(code, str) and len(code) <= 16:
            result["code"] = code
        return result


async def _probe_upstream() -> Dict[str, Any]:
    """Open the upstream session the way the relay does, then end it at once."""
    from app.agents.agent_config import get_session_config

    upstream = None
    try:
        upstream = await connect_upstream()
        await upstream.send(json.dumps(get_session_config(
            driver_id="readiness-probe",
            shift_id="readiness-probe",
            agent_id=settings.assemblyai_agent_id,
            include_greeting=False,
        )))
        while True:
            raw = await upstream.recv()
            if isinstance(raw, (bytes, bytearray)):
                continue
            try:
                data = json.loads(raw)
            except ValueError:
                continue
            kind = data.get("type") if isinstance(data, dict) else None
            if kind in ("session.ready", "session.updated"):
                return {"ok": True}
            if kind in ("session.error", "error"):
                code = data.get("code")
                suffix = f"_{code}" if isinstance(code, str) and len(code) <= 40 else ""
                return {"ok": False, "reason": f"session_rejected{suffix}"}
    except UpstreamNotConfigured as e:
        return {"ok": False, "reason": e.reason}
    except websockets.exceptions.ConnectionClosed:
        return {"ok": False, "reason": "upstream_closed_during_setup"}
    except Exception as e:
        _, reason, _ = classify_upstream_failure(e)
        return {"ok": False, "reason": reason}
    finally:
        if upstream is not None:
            try:
                await upstream.send(json.dumps({"type": "session.end"}))
            except Exception:
                pass
            try:
                await upstream.close()
            except Exception:
                pass


async def _bounded_upstream_probe() -> Dict[str, Any]:
    try:
        return await asyncio.wait_for(_probe_upstream(), PROBE_TIMEOUT)
    except asyncio.TimeoutError:
        return {"ok": False, "reason": "timeout"}


_cache: Optional[Tuple[float, Dict[str, Any]]] = None
_lock = asyncio.Lock()


async def readiness_report() -> Dict[str, Any]:
    """The `/health/ready` body. Cached briefly and single-flight, so polling it stays cheap."""
    global _cache
    async with _lock:
        now = time.monotonic()
        if _cache is not None and now - _cache[0] < READY_CACHE_SECONDS:
            return _cache[1]

        config = config_report()
        database, upstream = await asyncio.gather(_probe_database(), _bounded_upstream_probe())
        ready = all(config["required"].values()) and database["ok"] and upstream["ok"]
        report = {
            "ready": ready,
            "checked_at": datetime.now(timezone.utc).isoformat(),
            "config": config,
            "checks": {"database": database, "assemblyai_session": upstream},
        }
        if not ready:
            logger.warning(
                "[Readiness] not ready: missing=%s database=%s assemblyai_session=%s",
                [name for name, present in config["required"].items() if not present],
                database.get("reason", "ok"), upstream.get("reason", "ok"),
            )
        _cache = (now, report)
        return report


def reset_readiness_cache() -> None:
    global _cache
    _cache = None
