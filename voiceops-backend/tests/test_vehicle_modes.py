"""
Per-vehicle-mode ETAs: walking is a real mode, and each mode gets its own time for the
same route. OSRM and TomTom are replaced by mock transports, so these run offline.
"""
import asyncio
import logging

import httpx
import pytest
from fastapi import HTTPException

from app.agents.tool_registry import execute_tool
from app.api.routes import driver as driver_routes
from app.integrations import osrm
from app.integrations.traffic_routing import TrafficRoutingClient
from app.services import vehicle_modes
from app.services.eta_service import ETAService
from app.services.routing_service import FallbackHaversineProvider
from app.services.vehicle_modes import (
    BICYCLE_SPEED_KMH,
    WALKING_SPEED_KMH,
    VehicleMode,
    apply_mode_to_routes,
    duration_for_mode,
    parse_vehicle_mode,
    resolve_vehicle_mode,
)

# 5 km by road, 10 minutes by car
DISTANCE_M = 5000.0
DRIVING_S = 600.0

OSRM_OK = {
    "code": "Ok",
    "routes": [
        {"geometry": "abc", "distance": DISTANCE_M, "duration": DRIVING_S,
         "legs": [{"summary": "Broad Street", "distance": DISTANCE_M, "duration": DRIVING_S}]},
    ],
}
CONTEXT = {
    "driver_id": "test-driver-123",
    "latitude": 6.46,
    "longitude": 3.40,
    "current_delivery": {"id": "del-1", "address": "14 Broad Street, Lagos Island",
                         "latitude": 6.4541, "longitude": 3.3947},
}
ORIGIN, DESTINATION = (6.46, 3.40), (6.4541, 3.3947)


@pytest.fixture(autouse=True)
def fresh_caches():
    vehicle_modes._driver_mode_cache.clear()
    yield
    vehicle_modes._driver_mode_cache.clear()


@pytest.fixture
def osrm_server(monkeypatch):
    def handle(request):
        return httpx.Response(200, json=OSRM_OK)

    monkeypatch.setattr(osrm, "_get_client",
                        lambda: httpx.AsyncClient(transport=httpx.MockTransport(handle)))


# --- recognising modes ---------------------------------------------------------------------

@pytest.mark.parametrize("text", ["walking", "Walking", "walk", "Walker", "foot", "on foot", "Pedestrian"])
def test_walking_and_its_common_spellings_are_recognised(text):
    assert parse_vehicle_mode(text) is VehicleMode.WALKING


@pytest.mark.parametrize("text,mode", [
    ("car", VehicleMode.CAR), ("Sedan", VehicleMode.CAR), ("delivery van", VehicleMode.CAR),
    ("motorbike", VehicleMode.MOTORBIKE), ("Motorcycle", VehicleMode.MOTORBIKE),
    ("okada", VehicleMode.MOTORBIKE), ("scooter", VehicleMode.MOTORBIKE),
    ("bicycle", VehicleMode.BICYCLE), ("bike", VehicleMode.BICYCLE), ("cycling", VehicleMode.BICYCLE),
])
def test_other_modes_are_recognised(text, mode):
    assert parse_vehicle_mode(text) is mode


def test_motorbike_is_not_mistaken_for_a_bicycle():
    assert parse_vehicle_mode("Motorbike") is VehicleMode.MOTORBIKE


@pytest.mark.parametrize("text", [None, "", "  ", "hoverboard", "12345"])
def test_unrecognised_text_is_not_a_mode(text):
    assert parse_vehicle_mode(text) is None


def test_unknown_vehicle_falls_back_to_car_and_says_so(caplog):
    with caplog.at_level(logging.WARNING, logger="app.services.vehicle_modes"):
        assert resolve_vehicle_mode("hoverboard") is VehicleMode.CAR
    assert "hoverboard" in caplog.text


def test_unset_vehicle_falls_back_to_car_quietly(caplog):
    with caplog.at_level(logging.WARNING, logger="app.services.vehicle_modes"):
        assert resolve_vehicle_mode(None) is VehicleMode.CAR
        assert resolve_vehicle_mode("vehicle") is VehicleMode.CAR  # the profile route's placeholder
    assert caplog.text == ""


# --- the calculation -----------------------------------------------------------------------

def test_each_mode_gets_its_own_time_for_the_same_route():
    times = {m: duration_for_mode(m, DISTANCE_M, DRIVING_S) for m in VehicleMode}
    assert times[VehicleMode.CAR] == 600
    assert times[VehicleMode.WALKING] == round(DISTANCE_M / (WALKING_SPEED_KMH / 3.6)) == 3600
    assert times[VehicleMode.BICYCLE] == round(DISTANCE_M / (BICYCLE_SPEED_KMH / 3.6)) == 1200
    assert times[VehicleMode.MOTORBIKE] < times[VehicleMode.CAR]  # close to, never above, driving
    assert times[VehicleMode.MOTORBIKE] > times[VehicleMode.CAR] * 0.5
    assert len(set(times.values())) == 4
    assert times[VehicleMode.MOTORBIKE] < times[VehicleMode.CAR] < times[VehicleMode.BICYCLE] < times[VehicleMode.WALKING]


def test_walking_ignores_traffic_but_car_does_not():
    assert duration_for_mode(VehicleMode.WALKING, DISTANCE_M, 600) == duration_for_mode(
        VehicleMode.WALKING, DISTANCE_M, 1800)
    assert duration_for_mode(VehicleMode.CAR, DISTANCE_M, 1800) == 1800


def test_apply_mode_to_routes_keeps_geometry_and_the_driving_time():
    routes = [{"summary": "A", "distance": 5000, "duration": 600, "polyline": "p"}]
    (walking,) = apply_mode_to_routes(routes, "walking")
    assert walking["duration"] == 3600
    assert walking["driving_duration"] == 600
    assert walking["vehicle_mode"] == "walking"
    assert walking["polyline"] == "p" and walking["distance"] == 5000
    assert routes[0]["duration"] == 600  # input untouched


# --- OSRM ----------------------------------------------------------------------------------

def test_osrm_directions_differ_per_mode_on_the_same_route(osrm_server):
    def duration(vehicle_type):
        (route,) = asyncio.run(osrm.get_directions(*ORIGIN, *DESTINATION, vehicle_type=vehicle_type))
        return route["duration"], route["distance"], route["polyline"]

    car, moto, bike, walk = (duration(v) for v in ("car", "motorbike", "bicycle", "walking"))
    assert len({car[0], moto[0], bike[0], walk[0]}) == 4
    assert {r[1:] for r in (car, moto, bike, walk)} == {(5000, "abc")}  # same driving geometry
    assert duration(None) == car  # no vehicle set: car


def test_osrm_client_route_is_timed_for_the_mode(monkeypatch):
    def handle(request):
        return httpx.Response(200, json={"routes": [{"distance": DISTANCE_M, "duration": DRIVING_S,
                                                     "geometry": "g", "legs": []}]})

    real = httpx.AsyncClient
    monkeypatch.setattr(osrm.httpx, "AsyncClient",
                        lambda **kw: real(transport=httpx.MockTransport(handle)))
    car = asyncio.run(osrm.osrm_client.get_route(ORIGIN, DESTINATION))
    walk = asyncio.run(osrm.osrm_client.get_route(ORIGIN, DESTINATION, vehicle_type="walk"))
    assert car["duration_mins"] == 10.0 and walk["duration_mins"] == 60.0
    assert walk["vehicle_mode"] == "walking" and walk["distance_km"] == car["distance_km"]


# --- traffic-aware path --------------------------------------------------------------------

def _tomtom(monkeypatch):
    payload = {"routes": [{"summary": {"travelTimeInSeconds": 720, "trafficDelayInSeconds": 180,
                                        "lengthInMeters": 5000}, "legs": [{"points": []}]}]}
    real = httpx.AsyncClient
    from app.integrations import traffic_routing
    monkeypatch.setattr(traffic_routing.httpx, "AsyncClient",
                        lambda **kw: real(transport=httpx.MockTransport(
                            lambda request: httpx.Response(200, json=payload))))
    return TrafficRoutingClient(api_key="k")


def test_traffic_aware_eta_differs_per_mode(monkeypatch):
    client = _tomtom(monkeypatch)
    results = {v: asyncio.run(client.get_traffic_aware_eta(ORIGIN, DESTINATION, vehicle_type=v))
               for v in ("car", "motorbike", "bicycle", "walking")}
    assert results["car"]["eta_minutes"] == 12 and results["car"]["traffic_delay_minutes"] == 3.0
    assert results["walking"]["eta_minutes"] == 60 and results["walking"]["traffic_delay_minutes"] == 0
    assert results["bicycle"]["eta_minutes"] == 20
    assert results["motorbike"]["eta_minutes"] < results["car"]["eta_minutes"]
    assert len({r["eta_minutes"] for r in results.values()}) == 4
    assert results["walking"]["vehicle_mode"] == "walking"


# --- ETA service (drives proactive ETAs, order offers, customer texts) ---------------------

def test_eta_service_haversine_differs_per_mode():
    etas = {v: ETAService.compute_eta_minutes(ORIGIN, DESTINATION, 30.0, vehicle_type=v)
            for v in ("car", "motorbike", "bicycle", "walking")}
    assert etas["motorbike"] <= etas["car"] < etas["bicycle"] < etas["walking"]
    assert ETAService.compute_eta_minutes(ORIGIN, DESTINATION, 30.0) == etas["car"]


def test_eta_service_traffic_path_and_cache_are_per_mode(monkeypatch):
    from app.integrations import traffic_routing

    client = _tomtom(monkeypatch)
    monkeypatch.setattr(traffic_routing, "traffic_routing_client", client)
    service = ETAService()

    def eta(vehicle_type, delivery_id="d-1"):
        return asyncio.run(service.compute_eta_minutes_traffic_aware(
            ORIGIN, DESTINATION, delivery_id=delivery_id, vehicle_type=vehicle_type))

    car, walk = eta("car"), eta("walking")  # same delivery id: the cache must not cross modes
    assert car["eta_minutes"] == 12 and walk["eta_minutes"] == 60
    assert car["vehicle_mode"] == "car" and walk["vehicle_mode"] == "walking"
    assert eta("walking")["eta_minutes"] == 60  # a cache hit still reports walking


def test_routing_fallback_is_per_mode():
    provider = FallbackHaversineProvider()
    mins = {v: asyncio.run(provider.calculate_route(ORIGIN, DESTINATION, v))["duration_mins"]
            for v in ("car", "bicycle", "walking")}
    assert mins["car"] < mins["bicycle"] < mins["walking"]


# --- the ETA a driver hears and the card they see share one calculation --------------------

def test_spoken_eta_and_map_card_agree_for_a_walker(osrm_server):
    from app.agents.tools import navigation

    context = dict(CONTEXT, vehicle_type="Walking")
    result = asyncio.run(execute_tool("start_navigation", {"delivery_id": "del-1"}, context))
    assert result["route"]["duration_mins"] == 60  # 5 km at 5 km/h, not the 10 min car time

    # The relay draws the card from routes_to_stop() with the same session context.
    stop = navigation.resolve_stop("del-1", context)
    card = navigation.route_fields(navigation.fastest_route(asyncio.run(navigation.routes_to_stop(stop, context))))
    assert card["duration_mins"] == result["route"]["duration_mins"]

    car = asyncio.run(execute_tool("start_navigation", {"delivery_id": "del-1"},
                                   dict(CONTEXT, vehicle_type="car")))
    assert car["route"]["duration_mins"] == 10

    best = asyncio.run(execute_tool("get_best_route", {"delivery_id": "del-1"}, context))
    assert best["best_route"]["duration_mins"] == 60


def test_the_drivers_current_vehicle_beats_the_one_the_session_loaded(osrm_server, monkeypatch):
    async def driver_row(driver_id):
        return {"id": driver_id, "vehicle_type": "bicycle"}

    import app.db.queries as queries
    monkeypatch.setattr(queries, "get_driver_by_id", driver_row)
    result = asyncio.run(execute_tool("start_navigation", {"delivery_id": "del-1"},
                                      dict(CONTEXT, vehicle_type="car")))
    assert result["route"]["duration_mins"] == 20


# --- storing the vehicle -------------------------------------------------------------------

class _FakeTable:
    def __init__(self, sink):
        self.sink = sink

    def update(self, data):
        self.sink.append(data)
        return self

    def eq(self, *_):
        return self

    def execute(self):
        return type("R", (), {"data": [self.sink[-1]]})()


def _put(monkeypatch, vehicle_type):
    sink = []
    fake = type("Supabase", (), {"table": lambda self, name: _FakeTable(sink)})()
    monkeypatch.setattr(driver_routes, "get_supabase_client", lambda: fake)
    request = driver_routes.UpdateProfileRequest(vehicle_type=vehicle_type)
    result = asyncio.run(driver_routes.update_profile(request, {"id": "driver-1"}))
    return result, sink


def test_profile_accepts_walking(monkeypatch):
    result, sink = _put(monkeypatch, "walking")
    assert result == {"vehicle_type": "walking"} and sink == [{"vehicle_type": "walking"}]


def test_profile_rejects_an_unknown_vehicle_instead_of_timing_it_as_a_car(monkeypatch):
    with pytest.raises(HTTPException) as err:
        _put(monkeypatch, "hoverboard")
    assert err.value.status_code == 422
    assert "walking" in err.value.detail


def test_changing_vehicle_drops_the_cached_mode(monkeypatch):
    vehicle_modes._driver_mode_cache["driver-1"] = (10**9, VehicleMode.CAR)
    _put(monkeypatch, "walking")
    assert "driver-1" not in vehicle_modes._driver_mode_cache
