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
- accept_order: Accept the new order offered to the driver
- decline_order: Decline the new order offered to the driver
- get_shift_summary: Get shift statistics and progress
- alert_dispatcher: Alert dispatcher with priority message
- show_screen: Open an app screen (map, settings, summary, voice)
- end_conversation: Close the voice conversation when the driver is finished

When drivers ask "What is my next stop?" or similar questions, you MUST call the get_next_delivery tool to get the actual delivery information. Do not make up delivery information.

Routes and stops appear on the driver's in-app map automatically. After a delivery is marked delivered, call get_next_delivery and announce the next stop.

New orders can be offered to the driver at any time. Announce them briefly and call accept_order or decline_order only after the driver answers.

The driver's microphone remains open during the conversation. When they say they are done, say a short goodbye and call end_conversation. Do not call it while waiting for an answer.

Be concise and helpful in your responses."""
    return system_prompt


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
            },
            "voice": "anna"  # Specify voice for TTS
        }
    }


def get_session_config(driver_id: str, shift_id: str, 
                     agent_id: Optional[str] = None) -> Dict[str, Any]:
    """
    Build the complete session configuration for AssemblyAI Voice Agent.
    
    Args:
        driver_id: Driver ID for context
        shift_id: Shift ID for context
        agent_id: Optional stored agent ID to use instead of inline config
    
    Returns:
        Complete session configuration dictionary
    """
    if agent_id:
        # Use stored agent ID for proper AssemblyAI configuration
        return {
            "type": "session.update",
            "session": {
                "agent_id": agent_id
            }
        }
    
    # If no agent_id provided, use inline configuration
    # Import here to avoid circular dependency
    from app.agents.tool_registry import get_tools
    
    # Build dynamic context with defaults (DB not connected yet)
    driver_name = "Driver"
    vehicle_type = "vehicle"
    next_stop_info = ""
    
    # TODO: Fetch from DB when database is connected
    # For now, use defaults
    
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