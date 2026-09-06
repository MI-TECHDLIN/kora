"""
Simple test script to verify the tool registry works correctly.
"""
import asyncio
import sys
import os

# Add the app directory to the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


async def test_tool_registry():
    """Test that the tool registry is properly configured."""
    print("Testing Tool Registry...")
    
    try:
        from app.agents.tool_registry import TOOLS
        
        print(f"Found {len(TOOLS)} tools in registry")
        
        for tool in TOOLS:
            print(f"  - {tool['name']}: {tool['description']}")
        
        print("Tool registry test completed")
        return True
        
    except Exception as e:
        print(f"Tool registry test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


async def test_session_config():
    """Test that session config function works."""
    print("\nTesting Session Config Function...")
    
    try:
        from app.agents.tool_registry import build_session_config
        
        # Test with mock data (no DB required)
        config = await build_session_config("test-driver", "test-shift")
        
        print(f"Session config generated successfully")
        print(f"System prompt length: {len(config['session']['system_prompt'])} characters")
        print(f"Tools count: {len(config['session']['tools'])}")
        
        print("Session config test completed")
        return True
        
    except Exception as e:
        print(f"Session config test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


async def main():
    """Run all tests."""
    print("=" * 50)
    print("Tool Registry Test Suite")
    print("=" * 50)
    
    # Test 1: Tool registry
    registry_ok = await test_tool_registry()
    
    # Test 2: Session config
    if registry_ok:
        await test_session_config()
    
    print("\n" + "=" * 50)
    print("Test suite completed")
    print("=" * 50)


if __name__ == "__main__":
    asyncio.run(main())
