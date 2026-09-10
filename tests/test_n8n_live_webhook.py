"""
Quick manual test script for n8n dispatcher alert webhook.
Usage:
    python tests/test_n8n_live_webhook.py [--test]
"""
import sys
from pathlib import Path

# Add project root to sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import asyncio
from app.integrations.n8n_client import send_dispatcher_alert


async def main():
    use_test_webhook = "--test" in sys.argv
    webhook_url = (
        "http://localhost:5678/webhook-test/dispatcher-alert"
        if use_test_webhook
        else "http://localhost:5678/webhook/dispatcher-alert"
    )
    
    print(f"[SEND] Sending test alert to n8n webhook: {webhook_url}")
    
    result = await send_dispatcher_alert(
        driver_id="driver-voiceops-01",
        driver_name="David Adeleke",
        alert_type="safety_incident",
        message="Urgent: Road blocked by construction. Need alternate routing support at Broad St.",
        severity="critical",
        location="14 Broad Street, Lagos Island",
        shift_id="shift-2026-09-10",
        dispatcher_email="dispatcher@voiceops.app",
        webhook_url=webhook_url
    )
    
    print(f"Response: {result}")
    if result.get("success"):
        print("[SUCCESS] Alert delivered to n8n successfully!")
    else:
        print(f"[WARNING] Failed to deliver: {result.get('error')}")


if __name__ == "__main__":
    asyncio.run(main())
