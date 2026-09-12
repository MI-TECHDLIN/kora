"""
AssemblyAI Voice Agent configuration and prompts.
"""
from typing import Dict, Any, Optional, List
from app.agents.tool_registry import get_tools


def get_system_prompt(driver_name: str = "Driver", vehicle_type: str = "vehicle", 
                     shift_id: str = "", next_stop_info: str = "") -> str:
    """
    Generate the system prompt for the VoiceOps agent.
    
    Args:
        driver_name: Name of the driver
        vehicle_type: Type of vehicle
        shift_id: Current shift ID
        next_stop_info: Information about the next delivery stop
    
    Returns:
        The complete system prompt string
    """
    system_prompt = f"""You are VoiceOps, a voice assistant for delivery drivers.

IMPORTANT: You have access to tools that can help with deliveries. When drivers ask about their next stop, deliveries, routes, or need to communicate with customers, you MUST use the available tools to assist them.

Available tools:
- get_next_delivery: Get the next delivery in the current shift
- update_delivery_status: Update delivery status
- get_best_route: Get the best route with traffic information
- start_navigation: Start navigation to delivery location
- call_customer: Call the customer via phone
- notify_customer: Send SMS notification to customer
- get_next_order: Get the next order in the queue
- get_shift_summary: Get shift statistics and progress
- alert_dispatcher: Alert dispatcher with priority message

When drivers ask "What is my next stop?" or similar questions, you MUST call the get_next_delivery tool to get the actual delivery information. Do not make up delivery information.

Routes and stops appear on the driver's in-app map automatically when you use get_next_delivery, get_best_route, or start_navigation. Never tell the driver to open another maps app.

After a delivery is marked delivered, call get_next_delivery and announce the next stop.

Be concise and helpful in your responses."""

    driver_facts = [f"The driver's name is {driver_name}."]
    if vehicle_type and vehicle_type != "vehicle":
        driver_facts.append(f"They ride a {vehicle_type}.")
    if next_stop_info:
        driver_facts.append(f"Their current stop: {next_stop_info}.")
    return f"{system_prompt}\n\n{' '.join(driver_facts)}"


def get_agent_greeting() -> str:
    """Get the default greeting for the VoiceOps agent."""
    return "Hello! I'm your VoiceOps assistant. How can I help you with your deliveries today?"


def get_audio_config() -> Dict[str, Any]:
    """Get the audio configuration for AssemblyAI Voice Agent."""
    return {
        "input": {
            "format": {
                "encoding": "audio/pcm"
            }
        },
        "output": {
            "format": {
                "encoding": "audio/pcm"
            }
        }
    }


def get_session_config(driver_id: str, shift_id: str,
                     agent_id: Optional[str] = None,
                     driver_name: str = "Driver", vehicle_type: str = "vehicle",
                     next_stop_info: str = "") -> Dict[str, Any]:
    """
    Build the complete session configuration for AssemblyAI Voice Agent.

    Args:
        driver_id: Driver ID for context
        shift_id: Shift ID for context
        agent_id: Optional stored agent ID to use instead of inline config
        driver_name: Driver's name (the voice WebSocket loads it from the drivers row)
        vehicle_type: Driver's vehicle (drivers.vehicle_type)
        next_stop_info: One-line description of the delivery the driver is on

    Returns:
        Complete session configuration dictionary
    """
    if agent_id:
        # Use stored agent
        return {
            "type": "session.update",
            "session": {
                "agent_id": agent_id
            }
        }
    
    # Import here to avoid circular dependency
    from app.agents.tool_registry import get_tools
    
    # Build inline configuration
    return {
        "type": "session.update",
        "session": {
            "system_prompt": get_system_prompt(driver_name, vehicle_type, shift_id, next_stop_info),
            "greeting": get_agent_greeting(),
            **get_audio_config(),
            "tools": get_tools()
        }
    }