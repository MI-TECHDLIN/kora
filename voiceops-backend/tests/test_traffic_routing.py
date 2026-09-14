"""
Unit tests for traffic-aware routing functionality.
Tests traffic API integration, fallback behavior, and caching.
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from app.integrations.traffic_routing import TrafficRoutingClient
from app.services.eta_service import ETAService


@pytest.mark.asyncio
async def test_traffic_routing_client_success():
    """Test successful traffic-aware ETA calculation."""
    client = TrafficRoutingClient(api_key="test_key")
    
    mock_response = {
        "routes": [{
            "summary": {
                "travelTimeInSeconds": 720,  # 12 minutes
                "trafficDelayInSeconds": 180,  # 3 minutes delay
                "lengthInMeters": 5000,  # 5 km
            },
            "legs": [{
                "points": [[0, 0], [1, 1]]
            }]
        }]
    }
    
    with patch('httpx.AsyncClient') as mock_client:
        mock_http_client = AsyncMock()
        mock_response_obj = MagicMock()
        mock_response_obj.status_code = 200
        mock_response_obj.json.return_value = mock_response
        mock_http_client.get.return_value = mock_response_obj
        mock_client.return_value.__aenter__.return_value = mock_http_client
        
        result = await client.get_traffic_aware_eta((30.0, -97.0), (30.1, -97.1))
        
        assert result is not None
        assert result["success"] is True
        assert result["provider"] == "tomtom"
        assert result["eta_minutes"] == 12
        assert result["traffic_delay_minutes"] == 3.0
        assert result["distance_km"] == 5.0


@pytest.mark.asyncio
async def test_traffic_routing_client_no_api_key():
    """Test behavior when no API key is configured."""
    client = TrafficRoutingClient(api_key=None)
    
    result = await client.get_traffic_aware_eta((30.0, -97.0), (30.1, -97.1))
    
    assert result is None


@pytest.mark.asyncio
async def test_traffic_routing_client_timeout():
    """Test behavior when API request times out."""
    client = TrafficRoutingClient(api_key="test_key")
    
    with patch('httpx.AsyncClient') as mock_client:
        mock_http_client = AsyncMock()
        import httpx
        mock_http_client.get.side_effect = httpx.TimeoutException("Request timed out")
        mock_client.return_value.__aenter__.return_value = mock_http_client
        
        result = await client.get_traffic_aware_eta((30.0, -97.0), (30.1, -97.1))
        
        assert result is None


@pytest.mark.asyncio
async def test_traffic_routing_client_api_error():
    """Test behavior when API returns error response."""
    client = TrafficRoutingClient(api_key="test_key")
    
    with patch('httpx.AsyncClient') as mock_client:
        mock_http_client = AsyncMock()
        mock_response_obj = MagicMock()
        mock_response_obj.status_code = 500
        mock_http_client.get.return_value = mock_response_obj
        mock_client.return_value.__aenter__.return_value = mock_http_client
        
        result = await client.get_traffic_aware_eta((30.0, -97.0), (30.1, -97.1))
        
        assert result is None


@pytest.mark.asyncio
async def test_eta_service_traffic_aware_with_traffic_api():
    """Test ETA service with successful traffic API call."""
    eta_service = ETAService()
    
    mock_traffic_result = {
        "success": True,
        "eta_minutes": 15,
        "distance_km": 8.0,
        "traffic_delay_minutes": 4.0,
        "provider": "tomtom",
        "geometry": "test_geometry"
    }
    
    with patch('app.integrations.traffic_routing.traffic_routing_client') as mock_client:
        mock_client.get_traffic_aware_eta = AsyncMock(return_value=mock_traffic_result)
        
        result = await eta_service.compute_eta_minutes_traffic_aware(
            (30.0, -97.0),
            (30.1, -97.1),
            delivery_id="test-delivery-123"
        )
        
        assert result["eta_minutes"] == 15
        assert result["traffic_delay_minutes"] == 4.0
        assert result["provider"] == "tomtom"
        assert result["distance_km"] == 8.0


@pytest.mark.asyncio
async def test_eta_service_traffic_aware_fallback_to_haversine():
    """Test ETA service fallback to haversine when traffic API fails."""
    eta_service = ETAService()
    
    with patch('app.integrations.traffic_routing.traffic_routing_client') as mock_client:
        mock_client.get_traffic_aware_eta = AsyncMock(return_value=None)
        
        result = await eta_service.compute_eta_minutes_traffic_aware(
            (30.0, -97.0),
            (30.1, -97.1),
            delivery_id="test-delivery-123",
            current_speed_kmh=30.0
        )
        
        assert result["provider"] == "haversine"
        assert result["traffic_delay_minutes"] == 0.0
        assert result["eta_minutes"] > 0  # Should calculate some ETA


@pytest.mark.asyncio
async def test_eta_service_traffic_aware_caching():
    """Test that traffic API results are cached per delivery."""
    eta_service = ETAService()
    
    mock_traffic_result = {
        "success": True,
        "eta_minutes": 15,
        "distance_km": 8.0,
        "traffic_delay_minutes": 4.0,
        "provider": "tomtom",
        "geometry": "test_geometry"
    }
    
    with patch('app.integrations.traffic_routing.traffic_routing_client') as mock_client:
        mock_client.get_traffic_aware_eta = AsyncMock(return_value=mock_traffic_result)
        
        # First call should hit the API
        result1 = await eta_service.compute_eta_minutes_traffic_aware(
            (30.0, -97.0),
            (30.1, -97.1),
            delivery_id="test-delivery-123"
        )
        
        # Second call should use cache (API should not be called again)
        result2 = await eta_service.compute_eta_minutes_traffic_aware(
            (30.0, -97.0),
            (30.1, -97.1),
            delivery_id="test-delivery-123"
        )
        
        # Both should return the same result
        assert result1["eta_minutes"] == result2["eta_minutes"]
        assert result1["traffic_delay_minutes"] == result2["traffic_delay_minutes"]
        
        # API should have been called only once due to caching
        assert mock_client.get_traffic_aware_eta.call_count == 1


@pytest.mark.asyncio
async def test_eta_service_traffic_aware_no_delivery_id_no_cache():
    """Test that caching is skipped when no delivery_id is provided."""
    eta_service = ETAService()
    
    mock_traffic_result = {
        "success": True,
        "eta_minutes": 15,
        "distance_km": 8.0,
        "traffic_delay_minutes": 4.0,
        "provider": "tomtom",
        "geometry": "test_geometry"
    }
    
    with patch('app.integrations.traffic_routing.traffic_routing_client') as mock_client:
        mock_client.get_traffic_aware_eta = AsyncMock(return_value=mock_traffic_result)
        
        # Call without delivery_id - should hit API each time
        result1 = await eta_service.compute_eta_minutes_traffic_aware(
            (30.0, -97.0),
            (30.1, -97.1)
        )
        
        result2 = await eta_service.compute_eta_minutes_traffic_aware(
            (30.0, -97.0),
            (30.1, -97.1)
        )
        
        # API should be called twice since no delivery_id for caching
        assert mock_client.get_traffic_aware_eta.call_count == 2