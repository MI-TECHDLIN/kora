"""
Self-Ping Service: Keeps the Render backend awake by periodically pinging the health endpoint.

Render's free tier spins down instances after 15 minutes of inactivity. This service
periodically sends requests to the health endpoint to prevent spin-down.
"""
import asyncio
import logging
import httpx
from app.config import settings

logger = logging.getLogger(__name__)


class SelfPingService:
    """Background service that periodically pings the health endpoint to keep the instance awake."""
    
    def __init__(self):
        self._task: asyncio.Task | None = None
        self._running = False
        self._client: httpx.AsyncClient | None = None
        
    async def start(self):
        """Start the self-ping background task."""
        if not settings.self_ping_enabled:
            logger.info("[SelfPing] Self-ping disabled in configuration")
            return
            
        if settings.environment != "production":
            logger.info("[SelfPing] Self-ping only runs in production environment")
            return
            
        if self._running:
            logger.warning("[SelfPing] Self-ping service already running")
            return
            
        self._running = True
        self._client = httpx.AsyncClient(timeout=10.0)
        self._task = asyncio.create_task(self._ping_loop())
        logger.info(f"[SelfPing] Started self-ping service (interval: {settings.self_ping_interval_seconds}s)")
        
    async def stop(self):
        """Stop the self-ping background task."""
        if not self._running:
            return
            
        self._running = False
        
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None
            
        if self._client:
            await self._client.aclose()
            self._client = None
            
        logger.info("[SelfPing] Stopped self-ping service")
        
    async def _ping_loop(self):
        """Background loop that periodically pings the health endpoint."""
        while self._running:
            try:
                await self._ping_health()
                await asyncio.sleep(settings.self_ping_interval_seconds)
            except asyncio.CancelledError:
                logger.info("[SelfPing] Ping loop cancelled")
                break
            except Exception as e:
                logger.error(f"[SelfPing] Error in ping loop: {e}")
                await asyncio.sleep(settings.self_ping_interval_seconds)
                
    async def _ping_health(self):
        """Send a ping to the health endpoint."""
        if not self._client:
            return
            
        try:
            health_url = f"{settings.backend_url}/health"
            response = await self._client.get(health_url)
            
            if response.status_code == 200:
                logger.debug(f"[SelfPing] Health check successful: {health_url}")
            else:
                logger.warning(f"[SelfPing] Health check returned status {response.status_code}")
                
        except httpx.TimeoutException:
            logger.warning("[SelfPing] Health check timed out")
        except Exception as e:
            logger.error(f"[SelfPing] Health check failed: {e}")


# Global instance
self_ping_service = SelfPingService()