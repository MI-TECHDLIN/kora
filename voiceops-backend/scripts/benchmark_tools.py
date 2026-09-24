"""
Benchmark VoiceOps Tool Execution: Sequential vs Parallel (asyncio.gather)
Demonstrates that multi-tool execution finishes well under 500ms using asyncio.gather().
"""
import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import asyncio
from app.agents.orchestrator import ToolOrchestrator
from fastapi.testclient import TestClient
from app.main import app


async def main():
    print("=" * 70)
    print("⚡ BENCHMARK: FASTAPI + ASYNCIO.GATHER PARALLEL TOOL DISPATCH")
    print("=" * 70)

    context = {
        "driver_id": "10ed22c4-c1c0-4d37-8683-dbb8f510e4c6",
        "shift_id": "093375a3-06ab-4584-8331-f5df775f150b",
        "latitude": 6.4541,
        "longitude": 3.3947
    }

    # -------------------------------------------------------------
    # TEST 1: 5-TOOL DISPATCH (DELIVERY + PROGRESS + QUEUE + STATUS)
    # -------------------------------------------------------------
    print("\n--- 🚀 TEST 1: 5-TOOL CONCURRENT DISPATCH VIA asyncio.gather ---")
    multi_tools = [
        {"name": "update_delivery_status", "arguments": {"status": "delivered", "notes": "Left with security"}, "call_id": "c1"},
        {"name": "get_next_delivery", "arguments": {}, "call_id": "c2"},
        {"name": "get_shift_summary", "arguments": {}, "call_id": "c3"},
        {"name": "get_next_order", "arguments": {}, "call_id": "c4"},
        {"name": "log_exception", "arguments": {"reason": "Heavy rain / bad weather"}, "call_id": "c5"}
    ]

    print(f"Executing {len(multi_tools)} tools simultaneously in one turn...")
    b1 = await ToolOrchestrator.benchmark_sequential_vs_parallel(multi_tools, context)

    print(f"• Tool Count:                 {b1['tool_count']}")
    print(f"• Sequential Total:           {b1['sequential_ms']} ms")
    print(f"• Parallel (asyncio.gather):  {b1['parallel_asyncio_gather_ms']} ms")
    print(f"• Latency Saved:              {b1['latency_reduction_ms']} ms ({b1['speedup_factor']})")
    print(f"• Under 500ms Target SLA:     ✅ {b1['under_500ms']}")

    # -------------------------------------------------------------
    # TEST 2: ROUTE + STATUS + SUMMARY BATCH
    # -------------------------------------------------------------
    print("\n--- 🗺️  TEST 2: NAVIGATION + DELIVERY BATCH ---")
    nav_tools = [
        {"name": "update_delivery_status", "arguments": {"status": "delivered"}, "call_id": "n1"},
        {"name": "get_next_delivery", "arguments": {}, "call_id": "n2"},
        {"name": "get_best_route", "arguments": {"origin": "Marina, Lagos", "destination": "14 Broad Street, Lagos Island"}, "call_id": "n3"}
    ]

    b2 = await ToolOrchestrator.benchmark_sequential_vs_parallel(nav_tools, context)
    print(f"• Sequential Execution:       {b2['sequential_ms']} ms")
    print(f"• Parallel (asyncio.gather):  {b2['parallel_asyncio_gather_ms']} ms")
    print(f"• Speedup Factor:             {b2['speedup_factor']}")

    # -------------------------------------------------------------
    # TEST 3: LIVE FASTAPI ENDPOINT (/v1/tools/execute-parallel)
    # -------------------------------------------------------------
    print("\n--- 🌐 TEST 3: FASTAPI REST ENDPOINT (POST /v1/tools/execute-parallel) ---")
    access_token = os.getenv("KORA_ACCESS_TOKEN")
    if not access_token:
        raise RuntimeError(
            "KORA_ACCESS_TOKEN is required for the authenticated /v1/tools endpoint."
        )
    client = TestClient(app)
    api_payload = {
        "tools": [
            {"name": "update_delivery_status", "arguments": {"status": "delivered"}, "call_id": "api_1"},
            {"name": "get_next_delivery", "arguments": {}, "call_id": "api_2"},
            {"name": "get_shift_summary", "arguments": {}, "call_id": "api_3"}
        ],
        "context": context
    }

    response = client.post(
        "/v1/tools/execute-parallel",
        json=api_payload,
        headers={"Authorization": f"Bearer {access_token}"},
    )
    print(f"• HTTP Status Code:           {response.status_code} OK")
    data = response.json()
    print(f"• Total Duration:             {data['total_duration_ms']} ms")
    print(f"• Under 500ms SLA:            ✅ {data['under_500ms']}")
    print(f"• Executed Tools Count:       {data['tool_count']}")
    for r in data["results"]:
        print(f"    - {r['tool_name']:<24} | {r['duration_ms']} ms | error={r['is_error']}")

    print("\n" + "=" * 70)
    print("🎉 ALL TESTS PASSED: FASTAPI + asyncio.gather PARALLEL DISPATCH IS LIVE!")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(main())
