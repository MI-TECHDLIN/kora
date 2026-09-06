from abc import ABC, abstractmethod
from typing import Dict, Any, List, Optional
from app.db.client import get_supabase_client
from app.config import settings


class LogisticsAdapter(ABC):
    """
    Abstract base class for logistics platform adapters.
    All adapters must implement these three methods.
    """
    
    @abstractmethod
    async def get_tasks(self, driver_id: str) -> List[Dict[str, Any]]:
        """
        Fetch assigned tasks for a driver.
        Returns normalized delivery format.
        """
        pass
    
    @abstractmethod
    async def update_task_status(self, task_id: str, status: str) -> Dict[str, Any]:
        """
        Update task status on the platform.
        Returns confirmation.
        """
        pass
    
    @abstractmethod
    async def get_next_queued_order(self) -> Optional[Dict[str, Any]]:
        """
        Fetch next unassigned order from queue.
        Returns normalized order format or None.
        """
        pass


class MockAdapter(LogisticsAdapter):
    """
    Mock adapter with hardcoded Nigerian delivery data for demo/testing.
    """
    
    def __init__(self):
        # In-memory state for demo
        self._deliveries = [
            {
                "id": "mock-1",
                "recipient_name": "Amara Okonkwo",
                "address": "42 Adetokunbo Ademola Street, Victoria Island, Lagos",
                "phone": "+2348012345678",
                "status": "pending",
                "notes": "Gate code: 1234",
                "time_window": "10:00-12:00",
                "latitude": 6.4281,
                "longitude": 3.4219,
                "sequence_order": 1
            },
            {
                "id": "mock-2",
                "recipient_name": "Chinedu Eze",
                "address": "15 Awolowo Road, Ikoyi, Lagos",
                "phone": "+2348023456789",
                "status": "pending",
                "notes": "Call upon arrival",
                "time_window": "11:00-13:00",
                "latitude": 6.4576,
                "longitude": 3.4064,
                "sequence_order": 2
            },
            {
                "id": "mock-3",
                "recipient_name": "Fatima Ibrahim",
                "address": "8 Mobolaji Bank Anthony Way, Ikeja, Lagos",
                "phone": "+2348034567890",
                "status": "pending",
                "notes": "Leave at reception",
                "time_window": "12:00-14:00",
                "latitude": 6.6018,
                "longitude": 3.3515,
                "sequence_order": 3
            },
            {
                "id": "mock-4",
                "recipient_name": "Emeka Okafor",
                "address": "23 Allen Avenue, Ikeja, Lagos",
                "phone": "+2348045678901",
                "status": "pending",
                "notes": "Previously failed - customer unavailable",
                "time_window": "13:00-15:00",
                "latitude": 6.6059,
                "longitude": 3.3497,
                "sequence_order": 4
            },
            {
                "id": "mock-5",
                "recipient_name": "Grace Adebayo",
                "address": "7 Lekki-Epe Expressway, Lekki Phase 1, Lagos",
                "phone": "+2348056789012",
                "status": "pending",
                "notes": "Complex B, Flat 4",
                "time_window": "14:00-16:00",
                "latitude": 6.4386,
                "longitude": 3.4473,
                "sequence_order": 5
            },
            {
                "id": "mock-6",
                "recipient_name": "Oluwaseun Adeleke",
                "address": "19 Admiralty Way, Lekki Phase 1, Lagos",
                "phone": "+2348067890123",
                "status": "pending",
                "notes": "Use back entrance",
                "time_window": "15:00-17:00",
                "latitude": 6.4418,
                "longitude": 3.4462,
                "sequence_order": 6
            },
            {
                "id": "mock-7",
                "recipient_name": "Ngozi Mbah",
                "address": "3 Toyin Street, Ikeja, Lagos",
                "phone": "+2348078901234",
                "status": "pending",
                "notes": "Fragile package - handle with care",
                "time_window": "16:00-18:00",
                "latitude": 6.5992,
                "longitude": 3.3532,
                "sequence_order": 7
            }
        ]
    
    async def get_tasks(self, driver_id: str) -> List[Dict[str, Any]]:
        """Return mock deliveries."""
        return self._deliveries
    
    async def update_task_status(self, task_id: str, status: str) -> Dict[str, Any]:
        """Update mock delivery status in memory."""
        for delivery in self._deliveries:
            if delivery["id"] == task_id:
                delivery["status"] = status
                return {"success": True, "task_id": task_id, "status": status}
        return {"error": "Task not found"}
    
    async def get_next_queued_order(self) -> Optional[Dict[str, Any]]:
        """Return None for mock adapter (no queue)."""
        return None


class OnfleetAdapter(LogisticsAdapter):
    """
    Onfleet adapter for real logistics platform integration.
    """
    
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://onfleet.com/api/v2"
    
    async def _make_request(self, method: str, endpoint: str, data: Optional[dict] = None) -> dict:
        """Make authenticated request to Onfleet API."""
        import httpx
        import base64
        
        # Basic auth
        auth_string = base64.b64encode(f"{self.api_key}:".encode()).decode()
        headers = {
            "Authorization": f"Basic {auth_string}",
            "Content-Type": "application/json"
        }
        
        url = f"{self.base_url}/{endpoint}"
        
        async with httpx.AsyncClient() as client:
            if method == "GET":
                response = await client.get(url, headers=headers)
            elif method == "POST":
                response = await client.post(url, headers=headers, json=data)
            elif method == "PUT":
                response = await client.put(url, headers=headers, json=data)
            else:
                raise ValueError(f"Unsupported method: {method}")
            
            response.raise_for_status()
            return response.json()
    
    async def get_tasks(self, driver_id: str) -> List[Dict[str, Any]]:
        """Fetch tasks from Onfleet for a driver."""
        try:
            # Get tasks for driver
            tasks = await self._make_request("GET", f"tasks?driver={driver_id}")
            
            # Normalize to internal format
            normalized = []
            for task in tasks:
                normalized.append({
                    "id": task.get("id"),
                    "recipient_name": task.get("recipient", {}).get("name"),
                    "address": task.get("destination", {}).get("address", {}).get("unparsed"),
                    "phone": task.get("recipient", {}).get("phone"),
                    "status": task.get("state"),
                    "notes": task.get("notes"),
                    "time_window": f"{task.get('pickupTimeWindow')} - {task.get('deliveryTimeWindow')}",
                    "latitude": task.get("destination", {}).get("location", {}).get("lat"),
                    "longitude": task.get("destination", {}).get("location", {}).get("long"),
                    "sequence_order": task.get("sequence", 0)
                })
            
            return normalized
        except Exception as e:
            print(f"Onfleet API error: {e}")
            return []
    
    async def update_task_status(self, task_id: str, status: str) -> Dict[str, Any]:
        """Update task status on Onfleet."""
        try:
            # Map internal status to Onfleet status
            onfleet_status = {
                "delivered": "COMPLETED",
                "failed": "FAILED",
                "rescheduled": "SKIPPED"
            }.get(status, status)
            
            result = await self._make_request("POST", f"tasks/{task_id}/complete", {
                "success": onfleet_status == "COMPLETED"
            })
            
            return {"success": True, "task_id": task_id, "status": onfleet_status}
        except Exception as e:
            print(f"Onfleet update error: {e}")
            return {"error": str(e)}
    
    async def get_next_queued_order(self) -> Optional[Dict[str, Any]]:
        """Fetch next unassigned order from Onfleet."""
        try:
            # Get unassigned tasks
            tasks = await self._make_request("GET", "tasks?state=0")
            
            if not tasks:
                return None
            
            # Return first unassigned task
            task = tasks[0]
            return {
                "id": task.get("id"),
                "recipient_name": task.get("recipient", {}).get("name"),
                "address": task.get("destination", {}).get("address", {}).get("unparsed"),
                "status": "unassigned"
            }
        except Exception as e:
            print(f"Onfleet queue error: {e}")
            return None


def get_logistics_adapter(driver_id: str) -> LogisticsAdapter:
    """
    Factory function to get the appropriate logistics adapter for a driver.
    Reads driver's platform_connections from database.
    """
    try:
        supabase = get_supabase_client()
        # Fetch driver's platform connections
        response = (
            supabase.table("platform_connections")
            .select("*")
            .eq("driver_id", driver_id)
            .eq("status", "active")
            .execute()
        )
        
        if not response.data:
            # No connections, use mock
            return MockAdapter()
        
        # Get first active connection
        connection = response.data[0]
        platform = connection.get("platform")
        
        if platform == "onfleet" and settings.onfleet_api_key:
            return OnfleetAdapter(settings.onfleet_api_key)
        else:
            # Default to mock for demo or unsupported platforms
            return MockAdapter()
            
    except Exception as e:
        print(f"Error getting logistics adapter: {e}")
        return MockAdapter()
