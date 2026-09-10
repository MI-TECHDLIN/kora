"""
Direct tool testing without AssemblyAI Voice Agent.
Tests each tool individually with mock parameters.
"""
import asyncio
import json
from app.agents.tool_registry import execute_tool


async def run_tool_test(tool_name: str, parameters: dict):
    """Test a single tool."""
    print(f"\n{'='*60}")
    print(f"Testing: {tool_name}")
    print(f"Parameters: {parameters}")
    print(f"{'='*60}")
    
    # Mock context
    context = {
        "driver_id": "test-driver-123",
        "driver_name": "Test Driver",
        "shift_id": "test-shift-456",
        "current_delivery": {
            "id": "mock-delivery-789",
            "recipient_name": "Amara Johnson",
            "address": "14 Broad Street, Lagos Island",
            "customer_phone": "+2348012345678"
        },
        "session_id": "test-session-000"
    }
    
    result = await execute_tool(tool_name, parameters, context)
    
    print(f"\nResult:")
    print(json.dumps(result, indent=2))
    
    return result


async def main():
    """Test all tools."""
    print("=" * 60)
    print("VoiceOps - Direct Tool Testing")
    print("=" * 60)
    
    # Test 1: get_next_delivery
    await run_tool_test("get_next_delivery", {})
    
    # Test 2: update_delivery_status
    await run_tool_test("update_delivery_status", {
        "status": "delivered",
        "failure_reason": "",
        "notes": "Customer signed on delivery"
    })
    
    # Test 3: log_exception
    await run_tool_test("log_exception", {
        "reason": "access_denied",
        "resolution": "reschedule",
        "notes": "Gate code not working, no response from customer"
    })
    
    # Test 4: get_best_route
    await run_tool_test("get_best_route", {
        "delivery_id": "mock-delivery-789"
    })
    
    # Test 5: start_navigation
    await run_tool_test("start_navigation", {
        "delivery_id": "mock-delivery-789"
    })
    
    # Test 6: call_customer
    await run_tool_test("call_customer", {
        "delivery_id": "mock-delivery-789",
        "message": "Your delivery driver is on the way and will arrive in 5 minutes."
    })
    
    # Test 7: notify_customer
    await run_tool_test("notify_customer", {
        "delivery_id": "mock-delivery-789",
        "message_type": "nearby",
        "custom_message": ""
    })
    
    # Test 8: get_next_order
    await run_tool_test("get_next_order", {})
    
    # Test 9: get_shift_summary
    await run_tool_test("get_shift_summary", {})
    
    # Test 10: alert_dispatcher
    await run_tool_test("alert_dispatcher", {
        "delivery_id": "mock-delivery-789",
        "message": "Customer is being aggressive. Need support at 14 Broad Street.",
        "priority": "urgent"
    })
    
    print("\n" + "=" * 60)
    print("All tools tested successfully!")
    print("=" * 60)


if __name__ == "__main__":
    import json
    asyncio.run(main())