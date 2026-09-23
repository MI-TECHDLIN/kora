"""
AssemblyAI Voice Agent configuration and prompts.
"""
from random import SystemRandom
from typing import Dict, Any, Optional, List
from app.agents.tool_registry import get_tools


VOICES = {
    # American English
    "alba", "eve", "george", "jane", "jean", "mary", "michael",
    # British English
    "anna", "charles", "paul", "vera",
}
DEFAULT_VOICE = "anna"

_GREETING_QUESTIONS = (
    "What is one good thing that has happened on your route today?",
    "Is there anything you are looking forward to after your shift?",
    "What would make this shift feel like a win for you?",
    "Have you heard a song today that put you in a good mood?",
)
_GREETING_RANDOM = SystemRandom()


def resolve_voice(value: Optional[str] = None) -> str:
    """Resolve a voice ID against the allowlist, falling back to DEFAULT_VOICE (anna)."""
    v = (value or "").strip().lower()
    return v if v in VOICES else DEFAULT_VOICE


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
    system_prompt = f"""You are Kora, the co-rider for delivery drivers.

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
- get_preferences: Get all the driver's current preferences and settings
- set_preference: Set a specific preference (key-value pairs like auto_accept_orders=true, avoid_highways=true)
- clear_preference: Clear a specific preference
- reset_preferences: Reset all preferences to defaults

CUSTOMIZATION: Drivers can customize your behavior through voice commands. When drivers ask to change settings, use the preference tools. Common requests:
- "Always accept orders" → set_preference with key=auto_accept_orders, value=true
- "Never accept orders" → set_preference with key=auto_decline_orders, value=true
- "Only accept orders within 5 km" → set_preference with key=max_order_distance_km, value=5.0
- "Avoid highways" → set_preference with key=avoid_highways, value=true
- "Prefer residential areas" → set_preference with key=prefer_residential, value=true
- "Always call customers" → set_preference with key=always_call_before_delivery, value=true
- "Never call customers" → set_preference with key=never_call_customer, value=true
- "Send SMS when I deliver" → set_preference with key=always_send_sms, value=true
- "Tell me my preferences" → get_preferences
- "Reset my preferences" → reset_preferences

When drivers ask "What is my next stop?" or similar questions, you MUST call the get_next_delivery tool to get the actual delivery information. Do not make up delivery information.

Routes and stops appear on the driver's in-app map automatically. After a delivery is marked delivered, call get_next_delivery and announce the next stop.

New orders can be offered to the driver at any time. Announce them briefly and call accept_order or decline_order only after the driver answers.

Screen changes require voice confirmation unless the driver's current request explicitly asks to open, show, or go to that screen. If you are suggesting a screen change, ask one short question naming the destination, for example, "Open your summary?" Wait for the driver to say yes, then call show_screen. If the driver already asked to open that screen, call show_screen immediately and do not ask twice.

The driver's microphone remains open during the conversation. When they say they are done, say a short goodbye and call end_conversation. Do not call it while waiting for an answer.

Use a calm, warm, and friendly manner in every response. Be reassuring and respectful, including when a tool fails or the driver sounds rushed. Be concise and helpful."""

    driver_facts = [f"The driver's name is {driver_name}."]
    if vehicle_type and vehicle_type != "vehicle":
        driver_facts.append(f"They ride a {vehicle_type}.")
    if next_stop_info:
        driver_facts.append(f"Their current stop: {next_stop_info}.")
    return f"{system_prompt}\n\n{' '.join(driver_facts)}"


def get_agent_greeting(
    driver_name: str = "Driver", question_index: Optional[int] = None
) -> str:
    """Build a warm first greeting, with an injectable variation for tests."""
    if question_index is None:
        question = _GREETING_RANDOM.choice(_GREETING_QUESTIONS)
    else:
        question = _GREETING_QUESTIONS[question_index % len(_GREETING_QUESTIONS)]
    name = (driver_name or "").strip()
    salutation = f"Hello, {name}" if name and name.lower() != "driver" else "Hello there"
    return (f"{salutation}! I'm Kora, your co-rider. "
            f"You can customize how I help you by voice. Just say things like 'always accept orders' or 'never call customers'. "
            f"How has your day been so far? {question}")


def get_audio_config(voice: Optional[str] = None) -> Dict[str, Any]:
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
            "voice": resolve_voice(voice)  # Specify voice for TTS
        }
    }


def get_session_config(
    driver_id: str,
    shift_id: str,
    agent_id: Optional[str] = None,
    driver_name: str = "Driver",
    vehicle_type: str = "vehicle",
    next_stop_info: str = "",
    voice: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Build the complete session configuration for AssemblyAI Voice Agent.
    
    Args:
        driver_id: Driver ID for context
        shift_id: Shift ID for context
        agent_id: Optional stored agent ID to use instead of inline config
        driver_name: Driver name for the prompt
        vehicle_type: Driver vehicle for the prompt
        next_stop_info: Current next stop details for the prompt
        voice: Optional voice ID for TTS (validated against allowlist)
    
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
    
    return {
        "type": "session.update",
        "session": {
            "system_prompt": get_system_prompt(driver_name, vehicle_type, shift_id, next_stop_info),
            "greeting": get_agent_greeting(driver_name),
            **get_audio_config(voice),
            "tools": get_tools()
        }
    }
