"""
Unit tests covering the 6 design handoffs:
1. Honest sentiment scoring and dynamic location matching in LeMUR fallback.
2. Proactive dwell check-in geofence gating and driver-facing question.
3. Contract-compliant PROACTIVE_ALERT event structure and voice socket bridge.
4. Shift report duration and source indicator.
"""
import asyncio
from unittest.mock import AsyncMock, patch, MagicMock
from app.services.risk_engine import RiskEngine, RiskType, RiskSeverity
from app.intelligence.lemur_pipeline import LemurIntelligencePipeline
from app.api.websocket import events
from app.api.websocket.voice import present_proactive_alert, _sessions, VoiceSession


def test_lemur_fallback_honest_sentiment():
    """Verify fallback sentiment has estimated prefix and dynamic route extraction."""
    pipeline = LemurIntelligencePipeline()
    shift_stats = {"total": 10, "delivered": 8, "failed": 1, "success_rate": 80.0}
    deliveries = [
        {"id": "del-1", "address": "812 Lavaca St, Austin, TX"},
        {"id": "del-2", "address": "1200 Congress Ave, Austin, TX"},
    ]
    # Transcript mentions Lavaca St and an incident, but NOT Lagos
    transcript = (
        "Driver: Next stop.\n"
        "VoiceOps Assistant: Stop 1 is Lavaca St.\n"
        "Driver: There is a lot of traffic on Lavaca St and the gate is locked.\n"
    )
    result = pipeline._fallback_nlp_analysis(transcript, shift_stats, deliveries=deliveries)

    assert result["lemur_source"] == "voiceops_speech_intelligence_engine"
    assert result["is_estimated"] is True
    assert "(Estimated while AI analysis was unavailable)" in result["executive_summary"]
    assert "Overall sentiment estimated at" in result["executive_summary"]
    assert any("Lavaca St" in issue for issue in result["route_issues"])
    # Ensure no hardcoded Lagos locations appear
    for issue in result["route_issues"]:
        assert "Lagos" not in issue
        assert "Marina" not in issue


def test_idle_time_gated_outside_geofence():
    """Verify idle time is NOT flagged when driver is far from stop (e.g. in traffic)."""
    async def _run():
        risk_engine = RiskEngine()
        driver_id = "00000000-0000-0000-0000-000000000001"
        shift_id = "00000000-0000-0000-0000-000000000002"
        # Driver stationary at (30.2600, -97.7400)
        location_update = {"latitude": 30.2600, "longitude": -97.7400, "speed": 0.5}
        
        # Stop is at (30.2800, -97.7400), over 2 km away
        delivery = {
            "id": "00000000-0000-0000-0000-000000000003",
            "dropoff_latitude": 30.2800,
            "dropoff_longitude": -97.7400,
            "status": "pending",
            "attempt_count": 0,
            "recipient_name": "Alice",
            "address": "200 University Ave",
        }
        with patch("app.services.risk_engine.get_next_pending_delivery", new=AsyncMock(return_value=delivery)):
            result = await risk_engine._check_idle_time(driver_id, shift_id, location_update)
            # Should be None because driver is not within 100m geofence
            assert result is None

    asyncio.run(_run())


def test_idle_time_flagged_inside_geofence_with_driver_question():
    """Verify idle time flags a driver question when stationary within 100m of stop."""
    async def _run():
        risk_engine = RiskEngine()
        driver_id = "00000000-0000-0000-0000-000000000001"
        shift_id = "00000000-0000-0000-0000-000000000002"
        # Driver stationary within 20m of dropoff
        location_update = {"latitude": 30.2713, "longitude": -97.7455, "speed": 0.0}
        delivery = {
            "id": "00000000-0000-0000-0000-000000000003",
            "dropoff_latitude": 30.2714,
            "dropoff_longitude": -97.7456,
            "status": "pending",
            "attempt_count": 1,
            "recipient_name": "Sarah",
            "address": "812 Lavaca St",
        }
        mock_pings = [
            {"speed": 0.0, "pinged_at": "2026-09-19T10:05:00Z"},
            {"speed": 0.2, "pinged_at": "2026-09-19T10:04:45Z"},
            {"speed": 0.1, "pinged_at": "2026-09-19T10:04:30Z"},
            {"speed": 0.0, "pinged_at": "2026-09-19T10:04:15Z"},
            {"speed": 0.0, "pinged_at": "2026-09-19T10:04:00Z"},
            {"speed": 0.0, "pinged_at": "2026-09-19T10:03:45Z"},
        ]
        with patch("app.services.risk_engine.get_next_pending_delivery", new=AsyncMock(return_value=delivery)), \
             patch("app.services.risk_engine.get_recent_location_pings", new=AsyncMock(return_value=mock_pings)):
            result = await risk_engine._check_idle_time(driver_id, shift_id, location_update)
            assert result is not None
            assert result.risk_type == RiskType.EXCESSIVE_IDLE
            assert result.delivery_id == delivery["id"]
            assert result.evidence["at_stop"] is True
            assert result.evidence["prior_failures"] == 1
            # Check wording addresses driver directly and mentions prior failure
            assert "prior failed attempt" in result.recommended_action
            assert "stuck at a gate" in result.recommended_action

    asyncio.run(_run())


def test_proactive_alert_event_structure():
    """Verify events.proactive_alert matches docs/contracts/interface.md."""
    event = events.proactive_alert(
        severity="HIGH",
        risk_type="ROUTE_DEVIATION",
        message="Traffic ahead adds 8 minutes. Want me to reroute?",
        delivery_id="del-123",
        route_suggestion={"eta_minutes": 12, "current_eta_minutes": 20, "geometry": "xyz"},
    )
    assert event["event"] == "PROACTIVE_ALERT"
    assert event["severity"] == "HIGH"
    assert event["risk_type"] == "ROUTE_DEVIATION"
    assert event["delivery_id"] == "del-123"
    assert event["route_suggestion"]["eta_minutes"] == 12


def test_present_proactive_alert_bridge():
    """Verify present_proactive_alert emits to voice socket and queues announcement."""
    async def _run():
        driver_id = "driver-abc"
        shift_id = "shift-xyz"
        mock_session = MagicMock()
        mock_session.driver_id = driver_id
        mock_session.shift_id = shift_id
        mock_session.emit = AsyncMock()
        mock_session._announce = MagicMock()

        _sessions[shift_id] = {mock_session}
        try:
            alert_payload = {
                "event": "PROACTIVE_ALERT",
                "severity": "HIGH",
                "risk_type": "ROUTE_DEVIATION",
                "message": "Traffic ahead.",
            }
            instructions = "Tell the driver about the traffic delay."
            sent_count = await present_proactive_alert(
                driver_id=driver_id,
                alert_payload=alert_payload,
                spoken_instructions=instructions,
                shift_id=shift_id,
            )
            assert sent_count == 1
            mock_session.emit.assert_awaited_once_with(alert_payload)
            mock_session._announce.assert_called_once_with("risk:ROUTE_DEVIATION", instructions)
        finally:
            _sessions.pop(shift_id, None)

    asyncio.run(_run())
