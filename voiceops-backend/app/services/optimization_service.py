"""
Route Optimization Service
Optimizes stop sequences to minimize total transit time and mileage.
Implements a greedy nearest-neighbor solver with Timefold solver fallback.
"""
import logging
from typing import List, Dict, Any, Tuple
from app.services.location_service import haversine_distance
from app.integrations.timefold import timefold_client

logger = logging.getLogger(__name__)


class OptimizationService:
    async def optimize_route(
        self,
        driver_id: str,
        shift_id: str,
        deliveries: List[Dict[str, Any]],
        origin: Tuple[float, float],
    ) -> List[Dict[str, Any]]:
        """
        Orders deliveries into an optimal sequence.
        """
        if not deliveries:
            return []

        # Attempt Timefold optimization if configured
        try:
            problem = {
                "driver_id": driver_id,
                "shift_id": shift_id,
                "origin": {"lat": origin[0], "lng": origin[1]},
                "deliveries": deliveries,
            }
            solved = await timefold_client.solve(problem)
            if solved and "ordered_deliveries" in solved:
                return solved["ordered_deliveries"]
        except Exception as e:
            logger.info(f"[OptimizationService] Timefold bypass: {e}")

        # Fallback to deterministic Greedy Nearest-Neighbor
        return self._greedy_nearest_neighbor(deliveries, origin)

    def _greedy_nearest_neighbor(
        self,
        deliveries: List[Dict[str, Any]],
        origin: Tuple[float, float],
    ) -> List[Dict[str, Any]]:
        """
        Greedy Nearest-Neighbor heuristic:
        Iteratively selects the unvisited delivery closest to the current location.
        """
        unvisited = list(deliveries)
        ordered: List[Dict[str, Any]] = []
        curr_lat, curr_lng = origin

        seq = 1
        while unvisited:
            best_idx = 0
            best_dist = float("inf")

            for i, d in enumerate(unvisited):
                d_lat = d.get("dropoff_latitude") or d.get("latitude")
                d_lng = d.get("dropoff_longitude") or d.get("longitude")

                if d_lat is not None and d_lng is not None:
                    dist = haversine_distance(curr_lat, curr_lng, float(d_lat), float(d_lng))
                else:
                    dist = 9999999.0  # Put deliveries without coordinates last

                if dist < best_dist:
                    best_dist = dist
                    best_idx = i

            chosen = unvisited.pop(best_idx)
            chosen_copy = dict(chosen)
            chosen_copy["sequence_order"] = seq
            ordered.append(chosen_copy)

            # Move current position to chosen stop
            c_lat = chosen.get("dropoff_latitude") or chosen.get("latitude")
            c_lng = chosen.get("dropoff_longitude") or chosen.get("longitude")
            if c_lat is not None and c_lng is not None:
                curr_lat, curr_lng = float(c_lat), float(c_lng)

            seq += 1

        return ordered


optimization_service = OptimizationService()
