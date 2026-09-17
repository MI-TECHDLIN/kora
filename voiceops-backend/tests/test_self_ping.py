"""
Test the self-ping service to ensure it keeps the backend awake.
"""
import asyncio
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from app.services.self_ping_service import SelfPingService


@pytest.mark.asyncio
async def test_self_ping_service_starts_and_stops():
    """Test that the self-ping service can start and stop correctly."""
    # Mock the configuration to enable self-ping
    with patch('app.services.self_ping_service.settings') as mock_settings:
        mock_settings.self_ping_enabled = True
        mock_settings.environment = 'production'
        mock_settings.self_ping_interval_seconds = 1.0
        mock_settings.backend_url = 'http://localhost:8000'
        
        service = SelfPingService()
        
        # Start the service
        await service.start()
        assert service._running is True
        assert service._task is not None
        assert service._client is not None
        
        # Stop the service
        await service.stop()
        assert service._running is False
        assert service._task is None
        assert service._client is None


@pytest.mark.asyncio
async def test_self_ping_disabled_in_development():
    """Test that self-ping is disabled in development environment."""
    with patch('app.services.self_ping_service.settings') as mock_settings:
        mock_settings.self_ping_enabled = True
        mock_settings.environment = 'development'
        mock_settings.self_ping_interval_seconds = 1.0
        mock_settings.backend_url = 'http://localhost:8000'
        
        service = SelfPingService()
        await service.start()
        
        # Should not start in development
        assert service._running is False
        assert service._task is None


@pytest.mark.asyncio
async def test_self_ping_disabled_by_config():
    """Test that self-ping can be disabled via configuration."""
    with patch('app.services.self_ping_service.settings') as mock_settings:
        mock_settings.self_ping_enabled = False
        mock_settings.environment = 'production'
        mock_settings.self_ping_interval_seconds = 1.0
        mock_settings.backend_url = 'http://localhost:8000'
        
        service = SelfPingService()
        await service.start()
        
        # Should not start if disabled
        assert service._running is False
        assert service._task is None


@pytest.mark.asyncio
async def test_self_ping_sends_health_check():
    """Test that the service actually sends health check requests."""
    with patch('app.services.self_ping_service.settings') as mock_settings:
        mock_settings.self_ping_enabled = True
        mock_settings.environment = 'production'
        mock_settings.self_ping_interval_seconds = 0.5
        mock_settings.backend_url = 'http://localhost:8000'
        
        service = SelfPingService()
        
        # Mock the httpx client
        mock_response = MagicMock()
        mock_response.status_code = 200
        
        with patch('app.services.self_ping_service.httpx.AsyncClient') as mock_client_class:
            mock_client = AsyncMock()
            mock_client_class.return_value = mock_client
            mock_client.get = AsyncMock(return_value=mock_response)
            
            await service.start()
            
            # Let it run for one ping cycle
            await asyncio.sleep(1.0)
            
            # Verify health check was called
            mock_client.get.assert_called()
            call_args = mock_client.get.call_args
            assert 'health' in str(call_args)
            
            await service.stop()


@pytest.mark.asyncio
async def test_self_ping_handles_errors():
    """Test that the service handles network errors gracefully."""
    with patch('app.services.self_ping_service.settings') as mock_settings:
        mock_settings.self_ping_enabled = True
        mock_settings.environment = 'production'
        mock_settings.self_ping_interval_seconds = 0.5
        mock_settings.backend_url = 'http://localhost:8000'
        
        service = SelfPingService()
        
        with patch('app.services.self_ping_service.httpx.AsyncClient') as mock_client_class:
            mock_client = AsyncMock()
            mock_client_class.return_value = mock_client
            mock_client.get = AsyncMock(side_effect=Exception("Network error"))
            
            await service.start()
            
            # Let it run for one ping cycle (should handle error)
            await asyncio.sleep(1.0)
            
            # Service should still be running despite errors
            assert service._running is True
            
            await service.stop()


if __name__ == "__main__":
    # Quick manual test with mocking
    async def manual_test():
        print("Testing self-ping service...")
        
        # Test in production mode
        with patch('app.services.self_ping_service.settings') as mock_settings:
            mock_settings.self_ping_enabled = True
            mock_settings.environment = 'production'
            mock_settings.self_ping_interval_seconds = 2.0
            mock_settings.backend_url = 'http://localhost:8000'
            
            service = SelfPingService()
            print("Starting service...")
            await service.start()
            print(f"Service running: {service._running}")
            
            print("Letting it run for 6 seconds (should ping 3 times)...")
            await asyncio.sleep(6)
            
            print("Stopping service...")
            await service.stop()
            print(f"Service stopped: {not service._running}")
            
        print("Test completed!")
    
    asyncio.run(manual_test())