"""
Keep a second demo driver online and automatically accept reassigned orders.

Run this beside the real backend during the two-driver dispatch demo:

    python scripts/simulate_second_driver.py

The script provisions a dedicated Supabase Auth user and driver row, creates or reuses that
driver's active shift, posts fresh Austin location pings, and holds a real authenticated voice
WebSocket open. When the backend sends an ``order_offer`` event, the script calls the existing
``accept_order`` tool through the backend process and prints the result.

Required backend environment: SUPABASE_URL, SUPABASE_SERVICE_KEY, SUPABASE_ANON_KEY, and the
AssemblyAI settings needed by /ws/voice/{shift_id}. Press Ctrl+C for a clean socket close and
shift end.
"""
import argparse
import asyncio
import json
import os
import secrets
import signal
import sys
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import httpx
import websockets
from supabase import create_client

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.config import settings
from app.db.client import get_supabase_client

DEMO_DRIVER_EMAIL = "voiceops-second-driver@example.com"
DEMO_DRIVER_NAME = "Maria Demo"
DEMO_DRIVER_PHONE = "+15125550199"  # 555-01xx is reserved for fictional use
DEMO_VEHICLE = "Simulated delivery van"

# The existing "Maria" second-driver fixture from tests/test_order_dispatch.py: about 5 km
# outside downtown Austin. The real phone's no-ping fallback at DEMO_AREA_CENTER is nearer to
# every current MockAdapter drop-off, so the phone gets the first offer and Maria gets the next.
DEMO_LOCATION = (30.2990, -97.7035)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def websocket_url(base_url: str, shift_id: str) -> str:
    parsed = urlsplit(base_url.rstrip("/"))
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("--url must be an http:// or https:// backend URL")
    scheme = "wss" if parsed.scheme == "https" else "ws"
    path = f"{parsed.path.rstrip('/')}/ws/voice/{shift_id}"
    return urlunsplit((scheme, parsed.netloc, path, "", ""))


async def in_thread(call, *args):
    """Run one synchronous Supabase client operation without blocking the socket loop."""
    return await asyncio.to_thread(call, *args)


async def provision_driver() -> tuple[Any, str, str]:
    """Create/reuse the dedicated Auth user and matching public driver, then issue a fresh JWT."""
    if not settings.supabase_url or not settings.supabase_service_key or not settings.supabase_anon_key:
        raise RuntimeError("Set SUPABASE_URL, SUPABASE_SERVICE_KEY, and SUPABASE_ANON_KEY.")

    service = get_supabase_client()
    users = await in_thread(service.auth.admin.list_users, 1, 1000)
    user = next((item for item in users if (item.email or "").lower() == DEMO_DRIVER_EMAIL), None)
    password = secrets.token_urlsafe(32)
    attributes = {
        "password": password,
        "email_confirm": True,
        "user_metadata": {"name": DEMO_DRIVER_NAME, "simulation": "second-driver"},
    }
    if user is None:
        response = await in_thread(
            service.auth.admin.create_user,
            {"email": DEMO_DRIVER_EMAIL, **attributes},
        )
        user = response.user
        print(f"[SETUP] Created dedicated Supabase Auth user {DEMO_DRIVER_EMAIL}")
    else:
        response = await in_thread(service.auth.admin.update_user_by_id, str(user.id), attributes)
        user = response.user
        print(f"[SETUP] Reusing dedicated Supabase Auth user {DEMO_DRIVER_EMAIL}")
    if user is None:
        raise RuntimeError("Supabase did not return the second driver's Auth user.")

    driver_id = str(user.id)

    def upsert_driver() -> None:
        service.table("drivers").upsert({
            "id": driver_id,
            "phone": DEMO_DRIVER_PHONE,
            "name": DEMO_DRIVER_NAME,
            "vehicle_type": DEMO_VEHICLE,
            "updated_at": utc_now(),
        }).execute()

    await in_thread(upsert_driver)

    auth_client = create_client(settings.supabase_url, settings.supabase_anon_key)
    auth = await in_thread(
        auth_client.auth.sign_in_with_password,
        {"email": DEMO_DRIVER_EMAIL, "password": password},
    )
    if not auth.session or not auth.session.access_token:
        raise RuntimeError("Could not obtain a Supabase access token for the second driver.")
    return service, driver_id, auth.session.access_token


async def ensure_active_shift(service: Any, driver_id: str) -> tuple[str, bool]:
    """Return the demo driver's newest active shift, creating one when necessary."""
    def find_shift():
        return (
            service.table("shifts")
            .select("*")
            .eq("driver_id", driver_id)
            .eq("status", "active")
            .order("started_at", desc=True)
            .limit(1)
            .execute()
        )

    existing = await in_thread(find_shift)
    if existing.data:
        return str(existing.data[0]["id"]), False

    def create_shift():
        return service.table("shifts").insert({
            "driver_id": driver_id,
            "status": "active",
            "started_at": utc_now(),
        }).execute()

    created = await in_thread(create_shift)
    if not created.data:
        raise RuntimeError("Supabase did not create an active shift for the second driver.")
    return str(created.data[0]["id"]), True


async def insert_location_ping(service: Any, driver_id: str, shift_id: str) -> None:
    latitude, longitude = DEMO_LOCATION

    def insert() -> None:
        service.table("location_pings").insert({
            "driver_id": driver_id,
            "shift_id": shift_id,
            "latitude": latitude,
            "longitude": longitude,
            "pinged_at": utc_now(),
        }).execute()

    await in_thread(insert)


async def keep_location_fresh(
    service: Any,
    driver_id: str,
    shift_id: str,
    interval_seconds: float,
) -> None:
    while True:
        await asyncio.sleep(interval_seconds)
        await insert_location_ping(service, driver_id, shift_id)


async def accept_offer(
    client: httpx.AsyncClient,
    token: str,
    driver_id: str,
    shift_id: str,
    order_id: str,
) -> dict[str, Any]:
    """Execute the real accept_order handler inside the backend process that owns the offer."""
    response = await client.post(
        "/v1/tools/execute-parallel",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "tools": [{
                "name": "accept_order",
                "arguments": {"order_id": order_id},
                "call_id": f"second-driver-{order_id}",
            }],
            # Driver and active-shift identity come from the bearer token on the server.
            "context": {},
        },
    )
    response.raise_for_status()
    payload = response.json()
    results = payload.get("results") or []
    if not results or not isinstance(results[0].get("parsed_result"), dict):
        raise RuntimeError(f"Unexpected accept_order response: {payload}")
    return results[0]["parsed_result"]


async def watch_offers(
    socket,
    client: httpx.AsyncClient,
    token: str,
    driver_id: str,
    shift_id: str,
    stop: asyncio.Event,
) -> None:
    announced_online = False
    while not stop.is_set():
        try:
            raw = await asyncio.wait_for(socket.recv(), timeout=1.0)
        except asyncio.TimeoutError:
            continue

        if isinstance(raw, bytes):
            if not announced_online:
                announced_online = True
                print(
                    "[ONLINE] SECOND DRIVER SIMULATION IS LIVE. "
                    "Decline an order on the real phone; this terminal will accept the reassignment."
                )
            continue  # Voice audio is intentionally not played by this terminal simulator.
        try:
            event = json.loads(raw)
        except (TypeError, ValueError):
            continue
        if not isinstance(event, dict):
            continue
        if event.get("event") == "error":
            raise RuntimeError(f"Voice socket error [{event.get('code')}]: {event.get('message')}")
        if not announced_online:
            announced_online = True
            print(
                "[ONLINE] SECOND DRIVER SIMULATION IS LIVE. "
                "Decline an order on the real phone; this terminal will accept the reassignment."
            )
        if event.get("event") != "order_offer":
            continue

        order_id = str(event.get("order_id") or "")
        if not order_id:
            print("[OFFER] Received an offer without an order_id; cannot accept it.")
            continue
        print(
            f"\n[OFFER] SIMULATED DRIVER RECEIVED {order_id} | "
            f"{event.get('area') or 'unknown area'} | {event.get('distance_km')} km"
        )
        try:
            result = await accept_offer(client, token, driver_id, shift_id, order_id)
        except (httpx.HTTPError, KeyError, RuntimeError, TypeError, ValueError) as exc:
            print(f"[ACCEPT FAILED] {order_id}: {exc}")
            continue
        if result.get("success"):
            print(
                f"[ACCEPTED] SIMULATED DRIVER PICKED UP {order_id} | "
                f"now stop {result.get('sequence')} | {result.get('address')}"
            )
        else:
            print(f"[ACCEPT FAILED] {order_id}: {result.get('error') or result}")


async def end_shift(service: Any, driver_id: str, shift_id: str) -> None:
    def update() -> None:
        (
            service.table("shifts")
            .update({"status": "completed", "ended_at": utc_now()})
            .eq("id", shift_id)
            .eq("driver_id", driver_id)
            .eq("status", "active")
            .execute()
        )

    await in_thread(update)


def install_shutdown_handlers(stop: asyncio.Event) -> None:
    loop = asyncio.get_running_loop()

    def request_stop() -> None:
        if not stop.is_set():
            print("\n[STOP] Closing the simulated driver's voice session and ending its shift...")
            stop.set()

    for signum in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(signum, request_stop)
        except NotImplementedError:
            pass


async def run(base_url: str, ping_interval: float) -> None:
    stop = asyncio.Event()
    install_shutdown_handlers(stop)

    async with httpx.AsyncClient(base_url=base_url.rstrip("/"), timeout=10.0) as client:
        health = await client.get("/health")
        health.raise_for_status()
        print(f"[SETUP] Backend is reachable at {base_url.rstrip('/')}")

        service, driver_id, token = await provision_driver()
        shift_id, created = await ensure_active_shift(service, driver_id)
        print(f"[SETUP] {'Created' if created else 'Reusing'} active shift {shift_id}")

        try:
            await insert_location_ping(service, driver_id, shift_id)
            print(
                f"[LOCATION] Posting every {ping_interval:g}s from the existing "
                f"second-driver demo coordinate ({DEMO_LOCATION[0]}, {DEMO_LOCATION[1]})"
            )

            location_task = asyncio.create_task(
                keep_location_fresh(service, driver_id, shift_id, ping_interval)
            )
            offer_task = None
            try:
                uri = websocket_url(base_url, shift_id)
                print(f"[CONNECTING] Opening real voice socket {uri}")
                async with websockets.connect(
                    uri,
                    additional_headers={"Authorization": f"Bearer {token}"},
                    open_timeout=15.0,
                    ping_interval=20.0,
                    ping_timeout=20.0,
                ) as socket:
                    offer_task = asyncio.create_task(
                        watch_offers(socket, client, token, driver_id, shift_id, stop)
                    )
                    done, _ = await asyncio.wait(
                        (offer_task, location_task),
                        return_when=asyncio.FIRST_COMPLETED,
                    )
                    for task in done:
                        await task
            finally:
                if offer_task is not None:
                    offer_task.cancel()
                    await asyncio.gather(offer_task, return_exceptions=True)
                location_task.cancel()
                await asyncio.gather(location_task, return_exceptions=True)
        finally:
            await end_shift(service, driver_id, shift_id)
            print(f"[CLEANUP] Shift {shift_id} completed; simulated driver is offline.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:8000", help="backend base URL")
    parser.add_argument(
        "--ping-interval",
        type=float,
        default=15.0,
        help="seconds between Supabase location pings (default: 15)",
    )
    args = parser.parse_args()
    if args.ping_interval <= 0:
        parser.error("--ping-interval must be greater than zero")
    return args


def main() -> None:
    args = parse_args()
    try:
        asyncio.run(run(args.url, args.ping_interval))
    except KeyboardInterrupt:
        pass
    except Exception as exc:
        print(f"[FAILED] Second-driver simulation stopped: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
