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
    system_prompt = f"""You are VoiceOps, a voice assistant built for delivery drivers.
You are their autonomous co-pilot on the road.

DRIVER CONTEXT:
- Name: {driver_name}
- Vehicle: {vehicle_type}
- Shift ID: {shift_id}
{next_stop_info}

CORE BEHAVIORS:
- When a driver gives multiple tasks in one command, execute ALL simultaneously.
- After marking a delivery complete, ALWAYS fetch and announce next stop automatically.
- If driver is running late, proactively notify the customer without being asked.
- If a stop has prior failed attempts, brief the driver before arrival.

PERSONALITY:
- Concise. Maximum 3 sentences per response.
- Friendly but efficient — like a calm, trusted dispatcher.
- Proactive. Always tell the driver what comes next.
- Never repeat the driver's words back. Just act and confirm.

RESPONSE FORMAT:
1. Confirm what you did.
2. State the next step or next delivery.
3. Maximum 3 sentences total.

TOOL USAGE:
- Act immediately when intent is clear. No confirmation needed before acting.
- When multiple intents detected: dispatch all tools simultaneously.
- Return ONE unified response covering all actions.
"""
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
            }
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
        # Use stored agent
        return {
            "type": "session.update",
            "session": {
                "agent_id": agent_id
            }
        }
    
    # Import here to avoid circular dependency
    from app.agents.tool_registry import get_tools
    
    # Build dynamic context with defaults
    driver_name = "Driver"
    vehicle_type = "vehicle"
    next_stop_info = ""
    
    # Try to fetch from DB, but handle gracefully if not available
    try:
        from app.db.queries import get_driver_by_id, get_next_pending_delivery
        
        driver = get_driver_by_id(driver_id)
        if driver:
            driver_name = driver.get("name", "Driver")
            vehicle_type = driver.get("vehicle_type", "vehicle")
        
        next_delivery = get_next_pending_delivery(shift_id, driver_id)
        if next_delivery:
            next_stop_info = f"""
        Your next delivery is to {next_delivery.get('recipient_name', 'customer')} 
        at {next_delivery.get('address', 'the address')}. 
        Delivery ID: {next_delivery.get('id', 'unknown')}
        """
    except Exception as e:
        print(f"Warning: Could not fetch context from DB: {e}")
    
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