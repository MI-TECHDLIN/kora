"""
Tests for the OSRM directions integration (app/integrations/osrm.py) and the navigation tools
built on it. OSRM is replaced by an httpx MockTransport, so these run offline.
"""
import asyncio

import httpx
import pytest

from app.agents.tool_registry import execute_tool
from app.integrations import osrm

# Google's encoded polyline reference example, which OSRM's `geometries=polyline` also produces
POLYLINE = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

OSRM_OK = {
    "code": "Ok",
    "routes": [
        {"geometry": POLYLINE, "distance": 3204.6, "duration": 660.4, "weight": 700.1,
         "legs": [{"summary": "Victoria Bridge, Ahmadu Bello Way", "distance": 3204.6,
                   "duration": 660.4, "steps": []}]},
        {"geometry": "slow", "distance": 5400.0, "duration": 1260.0, "weight": 1300.0,
         "legs": [{"summary": "", "distance": 5400.0, "duration": 1260.0, "steps": []}]},
    ],
    "waypoints": [],
}
OSRM_NO_ROUTE = {"code": "NoRoute", "message": "Impossible route between points"}

CONTEXT = {
    "driver_id": "test-driver-123",
    "shift_id": "test-shift-456",
    "latitude": 6.46,
    "longitude": 3.40,
    "current_delivery": {"id": "del-1", "address": "14 Broad Street, Lagos Island",
                         "latitude": 6.4541, "longitude": 3.3947},
}


@pytest.fixture
def osrm_server(monkeypatch):
    """Serve OSRM responses from `server["reply"]` and record each request in `server["requests"]`."""
    server = {"reply": httpx.Response(200, json=OSRM_OK), "requests": []}

    def handle(request):
        server["requests"].append(request)
        reply = server["reply"]
        if isinstance(reply, Exception):
            raise reply
        return reply

    monkeypatch.setattr(osrm, "_get_client",
                        lambda: httpx.AsyncClient(transport=httpx.MockTransport(handle)))
    return server


def directions():
    return asyncio.run(osrm.get_directions(6.46, 3.40, 6.4541, 3.3947))


def test_request_uses_lng_lat_order_and_encoded_polyline(osrm_server, monkeypatch):
    monkeypatch.setattr(osrm.settings, "osrm_base_url", "http://osrm.internal:5000/")
    directions()
    request = osrm_server["requests"][0]
    assert request.url.path == "/route/v1/driving/3.4,6.46;3.3947,6.4541"
    assert request.url.host == "osrm.internal" and request.url.port == 5000
    params = request.url.params
    assert params["geometries"] == "polyline"
    assert params["overview"] == "full"
    assert params["alternatives"] == "true"
    assert params["steps"] == "true"


def test_default_base_url_is_the_public_demo(osrm_server):
    directions()
    assert str(osrm_server["requests"][0].url).startswith("https://router.project-osrm.org/route/v1/driving/")


def test_routes_parsed_to_directions_shape(osrm_server):
    assert directions() == [
        {"summary": "Victoria Bridge, Ahmadu Bello Way", "distance": 3205, "duration": 660,
         "polyline": POLYLINE},
        {"summary": "Route", "distance": 5400, "duration": 1260, "polyline": "slow"},
    ]


def test_no_route_found_is_empty(osrm_server):
    osrm_server["reply"] = httpx.Response(400, json=OSRM_NO_ROUTE)
    assert directions() == []


@pytest.mark.parametrize("reply", [
    httpx.ConnectError("unreachable"),
    httpx.ReadTimeout("timed out"),
    httpx.Response(502, text="<html>Bad Gateway</html>"),
    httpx.Response(400, json={"code": "InvalidQuery", "message": "Query string malformed"}),
])
def test_osrm_failure_is_empty(osrm_server, reply):
    osrm_server["reply"] = reply
    assert directions() == []


def test_start_navigation_route_from_osrm(osrm_server):
    result = asyncio.run(execute_tool("start_navigation", {"delivery_id": "del-1"}, CONTEXT))
    assert result["success"] is True
    assert result["route"] == {
        "polyline": POLYLINE,
        "summary": "Victoria Bridge, Ahmadu Bello Way",
        "distance_km": 3.2,
        "duration_mins": 11,
        "duration_text": "11 mins",
    }
    assert result["message"] == ("Route to 14 Broad Street, Lagos Island is on your map: "
                                 "11 mins via Victoria Bridge, Ahmadu Bello Way.")


def test_start_navigation_without_a_route_still_shows_the_stop(osrm_server):
    osrm_server["reply"] = httpx.Response(400, json=OSRM_NO_ROUTE)
    result = asyncio.run(execute_tool("start_navigation", {"delivery_id": "del-1"}, CONTEXT))
    assert result["success"] is True
    assert result["route"] is None
    assert (result["latitude"], result["longitude"]) == (6.4541, 3.3947)
    assert result["message"] == "14 Broad Street, Lagos Island is on your map."


def test_start_navigation_when_osrm_is_unreachable(osrm_server):
    osrm_server["reply"] = httpx.ConnectError("unreachable")
    result = asyncio.run(execute_tool("start_navigation", {"delivery_id": "del-1"}, CONTEXT))
    assert result["success"] is True and result["route"] is None


def test_get_best_route_from_osrm(osrm_server):
    result = asyncio.run(execute_tool("get_best_route", {"delivery_id": "del-1"}, CONTEXT))
    assert result["success"] is True
    assert result["best_route"]["summary"] == "Victoria Bridge, Ahmadu Bello Way"
    assert result["best_route"]["duration_text"] == "11 mins"
    assert result["has_faster_route"] is False
    assert result["all_routes"][0]["polyline"] == POLYLINE
