"""
The traffic ETA cache belongs to an ETAService instance, not to the class.

It used to be a class attribute, so every instance (and every test) shared one dict and a cached
ETA written by one leaked into the next, which made results depend on test order.
"""
import asyncio

import pytest

from app.integrations import traffic_routing
from app.services.eta_service import ETAService, eta_service

NEAR = ((30.2672, -97.7431), (30.2700, -97.7400))
FAR = ((30.2672, -97.7431), (30.4000, -97.6000))


@pytest.fixture(autouse=True)
def no_traffic_provider(monkeypatch):
    """Force the haversine path so the ETA depends only on the coordinates."""
    class Down:
        async def get_traffic_aware_eta(self, *args, **kwargs):
            return None

    monkeypatch.setattr(traffic_routing, "traffic_routing_client", Down())


def eta(service, route, delivery_id="del-1"):
    origin, destination = route
    return asyncio.run(service.compute_eta_minutes_traffic_aware(
        origin, destination, delivery_id=delivery_id))["eta_minutes"]


def test_instances_do_not_share_cached_etas():
    first, second = ETAService(), ETAService()

    near_eta = eta(first, NEAR)
    assert first._traffic_eta_cache and not second._traffic_eta_cache

    # Same delivery id, a much longer trip: a shared cache would hand back the short ETA
    assert eta(second, FAR) > near_eta


def test_cache_is_not_a_class_attribute():
    assert "_traffic_eta_cache" not in vars(ETAService)


def test_cache_still_serves_repeat_lookups_within_the_ttl():
    service = ETAService()
    first = eta(service, NEAR)
    # Same delivery id, different route: within the TTL the cached ETA wins
    assert eta(service, FAR) == first


def test_cache_expires_after_the_ttl():
    service = ETAService()
    first = eta(service, NEAR)
    for key, (stamp, result) in list(service._traffic_eta_cache.items()):
        service._traffic_eta_cache[key] = (stamp - service._cache_ttl_seconds - 1, result)
    assert eta(service, FAR) > first


def test_clear_cache_empties_it():
    service = ETAService()
    eta(service, NEAR)
    service.clear_cache()
    assert service._traffic_eta_cache == {}


@pytest.mark.parametrize("attempt", [1, 2])
def test_app_wide_service_starts_each_test_empty(attempt):
    """Runs twice and writes to the shared instance both times: neither may see the other's entry."""
    assert eta_service._traffic_eta_cache == {}
    eta(eta_service, NEAR)
    assert eta_service._traffic_eta_cache
