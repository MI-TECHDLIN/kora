"""
Unit tests for Twilio integration.
"""
import asyncio
from app.integrations.twilio_client import get_twilio_client, make_call, send_sms, _has_live_twilio_credentials


def test_twilio_client_initialized():
    """Verify Twilio client initializes with configured credentials, or returns None in mock mode."""
    client = get_twilio_client()
    if _has_live_twilio_credentials():
        assert client is not None
        assert client.account_sid.startswith("AC")
    else:
        assert client is None


def test_make_call_structure():
    """Verify make_call returns expected structure."""
    result = asyncio.run(make_call(
        to_phone="+2348012345678",
        message="Driver is arriving in 5 minutes.",
        delivery_id="del-test-123",
        recipient_name="Test Customer"
    ))
    assert isinstance(result, dict)
    assert result.get("success") is True
    assert "customer_name" in result
    assert result["customer_name"] == "Test Customer"
    assert "customer_phone" in result


def test_send_sms_structure():
    """Verify send_sms returns expected structure."""
    result = asyncio.run(send_sms(
        to_phone="+2348012345678",
        message="Driver is arriving in 5 minutes.",
        customer_name="Test Customer"
    ))
    assert isinstance(result, dict)
    assert result.get("success") is True
    assert "customer_name" in result
    assert result["customer_name"] == "Test Customer"
    assert "message_sent" in result
