"""
Timefold Optimization Integration
HTTP client for Timefold Vehicle Routing Problem (VRP) solver.
Falls back to local greedy solver if no remote Timefold engine is deployed.
"""
import logging
from typing import Dict, Any, Optional
import httpx
from app.config import settings

logger = logging.getLogger(__name__)


class TimefoldClient:
    def __init__(self, endpoint: Optional[str] = None):
        self.endpoint = endpoint or getattr(settings, "timefold_url", "http://localhost:8080/route-plans")

    async def solve(self, problem: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Submits vehicle routing problem to Timefold solver.
        """
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                res = await client.post(self.endpoint, json=problem)
                if res.status_code in [200, 201]:
                    return res.json()
        except Exception as e:
            logger.info(f"[Timefold] Solver unavailable ({e}), using local optimization engine.")
        return None


timefold_client = TimefoldClient()
