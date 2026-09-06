from typing import Dict, Any


# Tool definitions matching AssemblyAI Voice Agent API format
TOOLS = [
    {
        "name": "get_next_delivery",
        "description": "Get the next pending delivery stop for the current shift",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "update_delivery_status",
        "description": "Mark a delivery as delivered, failed, or rescheduled",
        "parameters": {
            "type": "object",
            "properties": {
                "status": {
                    "type": "string",
                    "enum": ["delivered", "failed", "rescheduled"],
                    "description": "The new status of the delivery"
                },
                "failure_reason": {
                    "type": "string",
                    "description": "Reason for failure if status is failed"
                },
                "notes": {
                    "type": "string",
                    "description": "Additional notes about the delivery"
                }
            },
            "required": ["status"]
        }
    },
    {
        "name": "log_exception",
        "description": "Log a delivery exception with reason and resolution path",
        "parameters": {
            "type": "object",
            "properties": {
                "reason": {
                    "type": "string",
                    "enum": ["customer_unavailable", "wrong_address", "access_denied", "damaged", "other"],
                    "description": "The reason for the exception"
                },
                "resolution": {
                    "type": "string",
                    "enum": ["reschedule", "leave_with_neighbor", "return_to_depot"],
                    "description": "How the exception was resolved"
                }
            },
            "required": ["reason", "resolution"]
        }
    },
    {
        "name": "get_best_route",
        "description": "Get the optimal current route to the next delivery with traffic data",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "start_navigation",
        "description": "Open Google Maps navigation to the next delivery",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "call_customer",
        "description": "Initiate a phone call to the customer via Twilio",
        "parameters": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                    "description": "Message to speak when call connects"
                }
            },
            "required": ["message"]
        }
    },
    {
        "name": "notify_customer",
        "description": "Send an SMS notification to the customer",
        "parameters": {
            "type": "object",
            "properties": {
                "message_type": {
                    "type": "string",
                    "enum": ["on_my_way", "nearby", "running_late", "missed", "custom"],
                    "description": "Type of message template to use"
                },
                "custom_message": {
                    "type": "string",
                    "description": "Custom message if message_type is custom"
                }
            },
            "required": ["message_type"]
        }
    },
    {
        "name": "get_next_order",
        "description": "Get the next order from the company queue",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "get_shift_summary",
        "description": "Get current shift progress statistics",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "alert_dispatcher",
        "description": "Alert the dispatcher about an urgent issue",
        "parameters": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                    "description": "The alert message"
                },
                "priority": {
                    "type": "string",
                    "enum": ["normal", "urgent"],
                    "description": "Priority level of the alert"
                }
            },
            "required": ["message"]
        }
    }
]


# SMS templates for customer notifications
SMS_TEMPLATES = {
    "on_my_way": "Your delivery is on the way! Driver will arrive shortly.",
    "nearby": "Driver is nearby with your delivery.",
    "running_late": "Driver is running a few minutes late. Will be there soon.",
    "missed": "Driver attempted delivery but couldn't reach you. Will retry shortly.",
    "custom": None  # Use custom_message field
}


async def build_session_config(driver_id: str, shift_id: str) -> Dict[str, Any]:
    """
    Build the session configuration for AssemblyAI Voice Agent API.
    Uses inline config (not stored agent) to allow per-session context injection.
    """
    # Build dynamic context with defaults for testing
    driver_name = "Driver"
    vehicle_type = "vehicle"
    next_stop_info = ""
    
    # Try to fetch from DB, but handle gracefully if not available
    try:
        from app.db.queries import get_driver_by_id, get_next_pending_delivery
        
        driver = await get_driver_by_id(driver_id)
        if driver:
            driver_name = driver.get("name", "Driver")
            vehicle_type = driver.get("vehicle_type", "vehicle")
        
        next_delivery = await get_next_pending_delivery(shift_id, driver_id)
        if next_delivery:
            next_stop_info = f"""
        Your next delivery is to {next_delivery.get('recipient_name', 'customer')} 
        at {next_delivery.get('address', 'the address')}. 
        Delivery ID: {next_delivery.get('id', 'unknown')}
        """
    except Exception as e:
        print(f"Warning: Could not fetch context from DB: {e}")
        # Continue with defaults
    
    # System prompt with injected context
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
    
    return {
        "type": "session.update",
        "session": {
            "system_prompt": system_prompt,
            "tools": TOOLS,
            "greeting": f"Hi {driver_name}, I'm VoiceOps. I'm ready to help with your deliveries."
        }
    }
