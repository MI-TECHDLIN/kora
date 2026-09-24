"""Focused checks for the standalone second-driver demo script."""
import asyncio
import json

import httpx

from app.integrations.logistics.mock_adapter import DEMO_AREA_CENTER, DROPOFFS
from app.utils.geo import haversine_km
from scripts import simulate_second_driver as simulator


def run(coro):
    return asyncio.run(coro)


def test_simulator_reuses_second_driver_fixture_and_ranks_after_demo_centre():
    assert simulator.DEMO_LOCATION == (30.2990, -97.7035)
    for _, latitude, longitude in DROPOFFS:
        assert haversine_km(*DEMO_AREA_CENTER, latitude, longitude) < haversine_km(
            *simulator.DEMO_LOCATION, latitude, longitude
        )


def test_websocket_url_tracks_backend_scheme_and_path():
    assert simulator.websocket_url("http://localhost:8000", "shift-1") == (
        "ws://localhost:8000/ws/voice/shift-1"
    )
    assert simulator.websocket_url("https://demo.example/api/", "shift-2") == (
        "wss://demo.example/api/ws/voice/shift-2"
    )


def test_accept_offer_calls_the_real_tool_endpoint_with_dispatch_context():
    seen = {}

    async def handler(request: httpx.Request) -> httpx.Response:
        seen["path"] = request.url.path
        seen["authorization"] = request.headers.get("authorization")
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json={
            "results": [{"parsed_result": {"success": True, "order_id": "order-1"}}],
            "tool_count": 1,
            "total_duration_ms": 1,
            "sequential_sum_ms": 1,
            "time_saved_ms": 0,
            "under_500ms": True,
        })

    async def scenario():
        async with httpx.AsyncClient(
            base_url="http://backend",
            transport=httpx.MockTransport(handler),
        ) as client:
            return await simulator.accept_offer(
                client, "access-token", "driver-1", "shift-1", "order-1"
            )

    assert run(scenario()) == {"success": True, "order_id": "order-1"}
    assert seen == {
        "path": "/v1/tools/execute-parallel",
        "authorization": "Bearer access-token",
        "body": {
            "tools": [{
                "name": "accept_order",
                "arguments": {"order_id": "order-1"},
                "call_id": "second-driver-order-1",
            }],
            "context": {},
        },
    }


def test_watch_offers_accepts_every_order_offer(capsys):
    stop = asyncio.Event()
    accepted = []

    class Socket:
        async def recv(self):
            return json.dumps({
                "event": "order_offer",
                "order_id": "order-2",
                "area": "Lavaca St, Austin",
                "distance_km": 2.4,
            })

    async def fake_accept(client, token, driver_id, shift_id, order_id):
        accepted.append((token, driver_id, shift_id, order_id))
        stop.set()
        return {"success": True, "sequence": 4, "address": "812 Lavaca St, Austin, TX"}

    original = simulator.accept_offer
    simulator.accept_offer = fake_accept
    try:
        run(simulator.watch_offers(Socket(), object(), "token", "driver", "shift", stop))
    finally:
        simulator.accept_offer = original

    assert accepted == [("token", "driver", "shift", "order-2")]
    output = capsys.readouterr().out
    assert "SIMULATED DRIVER RECEIVED order-2" in output
    assert "SIMULATED DRIVER PICKED UP order-2" in output
