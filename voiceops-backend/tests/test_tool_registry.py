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


def test_every_tool_schema_has_an_executor_and_is_well_formed():
    """The schemas sent to AssemblyAI and the executor map must describe the same tools.

    There is deliberately no hard-coded tool count: the registry is the source of truth, and
    tests/test_tool_docs.py fails when the docs stop matching it.
    """
    tools = get_tools()
    names = [tool["name"] for tool in tools]
    print(f"Registered tools ({len(names)}): {sorted(names)}")

    assert len(names) == len(set(names)), "duplicate tool name in get_tools()"
    assert set(names) == set(TOOL_EXECUTORS), (
        f"schemas without executors: {sorted(set(names) - set(TOOL_EXECUTORS))}; "
        f"executors without schemas: {sorted(set(TOOL_EXECUTORS) - set(names))}"
    )
    for tool in tools:
        assert tool["type"] == "function", tool["name"]
        assert tool["description"], f"{tool['name']} has no description"
        assert tool["parameters"]["type"] == "object", tool["name"]
        assert isinstance(tool["parameters"]["properties"], dict), tool["name"]
        for required in tool["parameters"].get("required", []):
            assert required in tool["parameters"]["properties"], f"{tool['name']}: {required}"


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
        test_every_tool_schema_has_an_executor_and_is_well_formed()
        test_accept_reroute_parameters()
        
        print("\n" + "="*50)
        print("All tool registry tests passed! [SUCCESS]")
        print("="*50)
    except Exception as e:
        print(f"\n[FAIL] Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)