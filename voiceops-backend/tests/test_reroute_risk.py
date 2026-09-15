"""
Unit tests for reroute suggestion functionality in risk engine.
Tests alternate route evaluation and ROUTE_DEVIATION risk detection.
"""
import pytest
from unittest.mock import AsyncMock, patch
from app.services.risk_engine import RiskEngine, RiskType, RiskSeverity


@pytest.mark.asyncio
async def test_check_reroute_available_with_savings():
    """Test reroute detection when alternate route saves meaningful time."""
    risk_engine = RiskEngine()
    
    # Setup mock data
    driver_id = "test-driver-123"
    shift_id = "test-shift-456"
    location_update = {
        "latitude": 30.0,
        "longitude": -97.0,
        "speed": 25.0
    }
    delivery = {
        "id": "delivery-789",
        "dropoff_latitude": 30.1,
        "dropoff_longitude": -97.1,
        "address": "123 Test St"
    }
    current_eta = 20  # Current route takes 20 minutes
    current_severity = RiskSeverity.HIGH
    
    # Mock traffic API to return a faster alternate route
    mock_alternate_route = {
        "success": True,
        "eta_minutes": 15,  # Alternate route saves 5 minutes
        "traffic_delay_minutes": 8.0,
        "geometry": "alternate_route_geometry"
    }
    
    with patch('app.integrations.traffic_routing.traffic_routing_client') as mock_client:
        mock_client.get_traffic_aware_eta = AsyncMock(return_value=mock_alternate_route)
        
        result = await risk_engine._check_reroute_available(
            driver_id, shift_id, location_update, delivery, current_eta, current_severity
        )
        
        assert result is not None
        assert result.risk_type == RiskType.ROUTE_DEVIATION
        assert result.severity == RiskSeverity.HIGH
        assert result.delivery_id == "delivery-789"
        assert result.driver_id == driver_id
        assert result.evidence["current_eta_minutes"] == 20
        assert result.evidence["alternate_eta_minutes"] == 15
        assert result.evidence["time_savings_minutes"] == 5
        assert result.evidence["traffic_delay_minutes"] == 8.0
        assert "Traffic ahead adds about 8 minutes" in result.recommended_action


@pytest.mark.asyncio
async def test_check_reroute_available_insufficient_savings():
    """Test that reroute is not suggested when time savings are minimal."""
    risk_engine = RiskEngine()
    
    driver_id = "test-driver-123"
    shift_id = "test-shift-456"
    location_update = {
        "latitude": 30.0,
        "longitude": -97.0,
        "speed": 25.0
    }
    delivery = {
        "id": "delivery-789",
        "dropoff_latitude": 30.1,
        "dropoff_longitude": -97.1,
        "address": "123 Test St"
    }
    current_eta = 20
    current_severity = RiskSeverity.HIGH
    
    # Mock traffic API to return a route with minimal savings (2 minutes)
    mock_alternate_route = {
        "success": True,
        "eta_minutes": 18,  # Only saves 2 minutes (below 3-minute threshold)
        "traffic_delay_minutes": 2.0,
        "geometry": "alternate_route_geometry"
    }
    
    with patch('app.integrations.traffic_routing.traffic_routing_client') as mock_client:
        mock_client.get_traffic_aware_eta = AsyncMock(return_value=mock_alternate_route)
        
        result = await risk_engine._check_reroute_available(
            driver_id, shift_id, location_update, delivery, current_eta, current_severity
        )
        
        # Should return None because savings are insufficient
        assert result is None


@pytest.mark.asyncio
async def test_check_reroute_available_low_severity():
    """Test that reroute check is skipped for low severity risks."""
    risk_engine = RiskEngine()
    
    driver_id = "test-driver-123"
    shift_id = "test-shift-456"
    location_update = {
        "latitude": 30.0,
        "longitude": -97.0,
        "speed": 25.0
    }
    delivery = {
        "id": "delivery-789",
        "dropoff_latitude": 30.1,
        "dropoff_longitude": -97.1,
        "address": "123 Test St"
    }
    current_eta = 20
    current_severity = RiskSeverity.LOW  # Low severity should skip reroute check
    
    result = await risk_engine._check_reroute_available(
        driver_id, shift_id, location_update, delivery, current_eta, current_severity
    )
    
    # Should return None for low severity
    assert result is None


@pytest.mark.asyncio
async def test_check_reroute_available_traffic_api_failure():
    """Test graceful handling when traffic API fails."""
    risk_engine = RiskEngine()
    
    driver_id = "test-driver-123"
    shift_id = "test-shift-456"
    location_update = {
        "latitude": 30.0,
        "longitude": -97.0,
        "speed": 25.0
    }
    delivery = {
        "id": "delivery-789",
        "dropoff_latitude": 30.1,
        "dropoff_longitude": -97.1,
        "address": "123 Test St"
    }
    current_eta = 20
    current_severity = RiskSeverity.HIGH
    
    with patch('app.integrations.traffic_routing.traffic_routing_client') as mock_client:
        mock_client.get_traffic_aware_eta = AsyncMock(return_value=None)
        
        result = await risk_engine._check_reroute_available(
            driver_id, shift_id, location_update, delivery, current_eta, current_severity
        )
        
        # Should return None gracefully when API fails
        assert result is None


@pytest.mark.asyncio
async def test_check_reroute_available_missing_coordinates():
    """Test handling of missing coordinates."""
    risk_engine = RiskEngine()
    
    driver_id = "test-driver-123"
    shift_id = "test-shift-456"
    location_update = {
        "latitude": None,  # Missing coordinates
        "longitude": -97.0,
        "speed": 25.0
    }
    delivery = {
        "id": "delivery-789",
        "dropoff_latitude": 30.1,
        "dropoff_longitude": -97.1,
        "address": "123 Test St"
    }
    current_eta = 20
    current_severity = RiskSeverity.HIGH
    
    result = await risk_engine._check_reroute_available(
        driver_id, shift_id, location_update, delivery, current_eta, current_severity
    )
    
    # Should return None with missing coordinates
    assert result is None


@pytest.mark.asyncio
async def test_check_reroute_available_invalid_driver_id():
    """Test handling of invalid driver ID."""
    risk_engine = RiskEngine()
    
    invalid_driver_id = "not-a-uuid"
    shift_id = "test-shift-456"
    location_update = {
        "latitude": 30.0,
        "longitude": -97.0,
        "speed": 25.0
    }
    delivery = {
        "id": "delivery-789",
        "dropoff_latitude": 30.1,
        "dropoff_longitude": -97.1,
        "address": "123 Test St"
    }
    current_eta = 20
    current_severity = RiskSeverity.HIGH
    
    result = await risk_engine._check_reroute_available(
        invalid_driver_id, shift_id, location_update, delivery, current_eta, current_severity
    )
    
    # Should return None for invalid driver ID
    assert result is None


@pytest.mark.asyncio
async def test_time_window_with_reroute_integration():
    """Test that reroute check is integrated into time window risk evaluation."""
    risk_engine = RiskEngine()
    
    driver_id = "test-driver-123"
    shift_id = "test-shift-456"
    location_update = {
        "latitude": 30.0,
        "longitude": -97.0,
        "speed": 25.0
    }
    
    # Mock delivery with time window risk
    mock_delivery = {
        "id": "delivery-789",
        "dropoff_latitude": 30.1,
        "dropoff_longitude": -97.1,
        "time_window_end": "2026-09-14T10:00:00Z",
        "address": "123 Test St"
    }
    
    # Mock traffic API for both ETA calculation and reroute check
    mock_traffic_result = {
        "success": True,
        "eta_minutes": 25,  # Will trigger time window risk
        "distance_km": 10.0,
        "traffic_delay_minutes": 8.0,
        "provider": "tomtom",
        "geometry": "route_geometry"
    }
    
    mock_alternate_route = {
        "success": True,
        "eta_minutes": 18,  # Saves 7 minutes
        "traffic_delay_minutes": 8.0,
        "geometry": "alternate_geometry"
    }
    
    with patch('app.services.risk_engine.get_next_pending_delivery') as mock_get_delivery:
        mock_get_delivery.return_value = mock_delivery
        
        with patch('app.services.eta_service.eta_service') as mock_eta_service:
            mock_eta_service.compute_eta_minutes_traffic_aware = AsyncMock(return_value=mock_traffic_result)
            mock_eta_service.update_delivery_eta = AsyncMock()
            mock_eta_service.check_time_window_risk = AsyncMock(return_value={
                "risk": "HIGH",
                "minutes_late": 15,
                "delivery_id": "delivery-789"
            })
            
            with patch('app.integrations.traffic_routing.traffic_routing_client') as mock_client:
                mock_client.get_traffic_aware_eta = AsyncMock(return_value=mock_alternate_route)
                
                result = await risk_engine._check_time_window(driver_id, shift_id, location_update)
                
                # Should return ROUTE_DEVIATION risk instead of TIME_WINDOW_RISK
                assert result is not None
                assert result.risk_type == RiskType.ROUTE_DEVIATION
                assert result.severity == RiskSeverity.HIGH