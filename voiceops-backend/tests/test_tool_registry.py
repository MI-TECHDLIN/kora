"""
Test that the new accept_reroute tool is properly registered.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.agents.tool_registry import get_tools, TOOL_EXECUTORS


def test_accept_reroute_tool_registered():
    """Test that accept_reroute tool is registered."""
    print("Testing accept_reroute tool registration...")
    
    tools = get_tools()
    tool_names = [tool["name"] for tool in tools]
    
    print(f"Available tools: {tool_names}")
    
    assert "accept_reroute" in tool_names, "accept_reroute tool not found in tool registry"
    print("[PASS] accept_reroute tool is registered")
    
    # Check tool properties
    accept_reroute_tool = next(tool for tool in tools if tool["name"] == "accept_reroute")
    assert accept_reroute_tool["type"] == "function"
    assert "description" in accept_reroute_tool
    assert "parameters" in accept_reroute_tool
    print(f"[PASS] accept_reroute tool has correct structure")
    print(f"Description: {accept_reroute_tool['description']}")
    
    # Check executor mapping
    assert "accept_reroute" in TOOL_EXECUTORS
    print("[PASS] accept_reroute executor is mapped")


def test_tool_count():
    """Test that we have 14 tools total."""
    print("Testing total tool count...")
    
    tools = get_tools()
    print(f"Total tools registered: {len(tools)}")
    
    assert len(tools) == 14, f"Expected 14 tools, got {len(tools)}"
    print("[PASS] Tool count is 14")


def test_accept_reroute_parameters():
    """Test that accept_reroute has correct parameters."""
    print("Testing accept_reroute parameters...")
    
    tools = get_tools()
    accept_reroute_tool = next(tool for tool in tools if tool["name"] == "accept_reroute")
    
    params = accept_reroute_tool["parameters"]
    assert params["type"] == "object"
    assert "properties" in params
    
    properties = params["properties"]
    print(f"Parameters: {list(properties.keys())}")
    
    # Check for expected parameters
    expected_params = ["eta_minutes", "geometry", "delivery_id"]
    for param in expected_params:
        assert param in properties, f"Expected parameter {param} not found"
    
    print("[PASS] accept_reroute has correct parameters")


if __name__ == "__main__":
    print("Running tool registry tests...\n")
    
    try:
        test_accept_reroute_tool_registered()
        test_tool_count()
        test_accept_reroute_parameters()
        
        print("\n" + "="*50)
        print("All tool registry tests passed! [SUCCESS]")
        print("="*50)
    except Exception as e:
        print(f"\n[FAIL] Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)