import asyncio
import pytest
from unittest.mock import patch, AsyncMock, MagicMock
from app.integrations.n8n_client import send_dispatcher_alert, trigger_dispatcher_alert_background


def test_send_dispatcher_alert_payload_format():
    async def _run():
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_resp = MagicMock()
            mock_resp.status_code = 200
            mock_resp.json.return_value = {"status": "received"}
            mock_resp.raise_for_status.return_value = None
            mock_post.return_value = mock_resp
            
            result = await send_dispatcher_alert(
                driver_id="driver-101",
                driver_name="Alex Smith",
                alert_type="safety_incident",
                message="Accident on 5th Avenue",
                severity="critical",
                location="5th Ave & 42nd St",
                shift_id="shift-999",
                webhook_url="http://localhost:5678/webhook/dispatcher-alert"
            )
            
            assert result["success"] is True
            assert result["status_code"] == 200
            
            # Verify payload matches n8n Set node requirements
            mock_post.assert_called_once()
            _, kwargs = mock_post.call_args
            payload = kwargs["json"]
            assert payload["driver_id"] == "driver-101"
            assert payload["driver_name"] == "Alex Smith"
            assert payload["alert_type"] == "safety_incident"
            assert payload["severity"] == "critical"
            assert payload["message"] == "Accident on 5th Avenue"
            assert payload["location"] == "5th Ave & 42nd St"
            assert payload["shift_id"] == "shift-999"
            assert "timestamp" in payload

    asyncio.run(_run())


def test_send_dispatcher_alert_unconfigured():
    async def _run():
        result = await send_dispatcher_alert(
            driver_id="driver-101",
            driver_name="Alex Smith",
            alert_type="dispatcher_alert",
            message="Running 10 mins late",
            webhook_url="https://your-n8n-instance.com/webhook/dispatcher-alert"
        )
        assert result["success"] is False
        assert result.get("mock") is True

    asyncio.run(_run())
