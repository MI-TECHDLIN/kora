"""
Synchronous tests for traffic routing functionality.
Tests basic functionality without async complications.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.integrations.traffic_routing import TrafficRoutingClient
from app.services.eta_service import ETAService


def test_traffic_routing_client_no_api_key():
    """Test behavior when no API key is configured."""
    print("Testing TrafficRoutingClient with no API key...")
    client = TrafficRoutingClient(api_key=None)
    assert client.api_key is None
    print("[PASS] Client created successfully with no API key")


def test_eta_service_initialization():
    """Test ETA service initialization."""
    print("Testing ETAService initialization...")
    eta_service = ETAService()
    assert hasattr(eta_service, 'URBAN_FACTOR')
    assert hasattr(eta_service, '_traffic_eta_cache')
    assert hasattr(eta_service, '_cache_ttl_seconds')
    print("[PASS] ETAService initialized with traffic attributes")


def test_eta_service_haversine_fallback():
    """Test haversine-based ETA calculation (fallback)."""
    print("Testing haversine-based ETA calculation...")
    eta_service = ETAService()
    
    # Test the fallback method
    origin = (30.0, -97.0)
    destination = (30.1, -97.1)
    eta = eta_service.compute_eta_minutes(origin, destination, current_speed_kmh=30.0)
    
    assert eta > 0
    assert isinstance(eta, int)
    print(f"[PASS] Haversine ETA calculation: {eta} minutes")


def test_eta_service_urban_factor():
    """Test that urban factor is applied correctly."""
    print("Testing urban factor application...")
    eta_service = ETAService()
    assert eta_service.URBAN_FACTOR == 1.35
    print("[PASS] Urban factor is correctly set to 1.35")


def test_cache_initialization():
    """Test that cache is properly initialized."""
    print("Testing cache initialization...")
    eta_service = ETAService()
    assert isinstance(eta_service._traffic_eta_cache, dict)
    assert len(eta_service._traffic_eta_cache) == 0
    assert eta_service._cache_ttl_seconds == 75
    print("[PASS] Cache initialized correctly")


def test_config_has_tomtom_setting():
    """Test that config has TomTom API key setting."""
    print("Testing config for TomTom API key setting...")
    from app.config import settings
    assert hasattr(settings, 'tomtom_api_key')
    print("[PASS] Config has tomtom_api_key attribute")


if __name__ == "__main__":
    print("Running synchronous traffic routing tests...\n")
    
    try:
        test_traffic_routing_client_no_api_key()
        test_eta_service_initialization()
        test_eta_service_haversine_fallback()
        test_eta_service_urban_factor()
        test_cache_initialization()
        test_config_has_tomtom_setting()
        
        print("\n" + "="*50)
        print("All synchronous tests passed! [SUCCESS]")
        print("="*50)
    except Exception as e:
        print(f"\n[FAIL] Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)