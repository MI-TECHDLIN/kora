"""
Push one generated order through the real Order Intake API, signed like a logistics platform's
webhook. Useful to trigger an offer on demand instead of waiting for the random feed.

    LOGISTICS_WEBHOOK_SECRET=... python scripts/push_demo_order.py [--url http://localhost:8000]
"""
import argparse
import json
import os
import sys

import httpx

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.api.routes.logistics import sign_body  # noqa: E402
from app.config import settings  # noqa: E402
from app.integrations.logistics import MockAdapter  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:8000", help="backend base URL")
    args = parser.parse_args()

    secret = settings.logistics_webhook_secret
    if not secret:
        sys.exit("Set LOGISTICS_WEBHOOK_SECRET (the same value the backend runs with).")

    payload = MockAdapter(1, 1).build_order_event()
    body = json.dumps(payload).encode()
    response = httpx.post(f"{args.url.rstrip('/')}/v1/logistics/orders", content=body, timeout=10,
                          headers={"Content-Type": "application/json", "X-VoiceOps-Signature": sign_body(body, secret)})
    print(response.status_code, response.text)


if __name__ == "__main__":
    main()
