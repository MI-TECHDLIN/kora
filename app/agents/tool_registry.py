"""
Tool registry for AssemblyAI Voice Agent.
Manages tool definitions and registration.
"""
from typing import Dict, Any, List


# Tool definitions matching AssemblyAI Voice Agent API format
TOOLS = [
    {
        "type": "function",
        "name": "get_next_delivery",
        "description": "Get the next pending delivery stop for the current shift",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "type": "function",
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
        "type": "function",
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
                    "description": "How the exception was resolved"
                }
            },
            "required": ["reason"]
        }
    },
    {
        "type": "function",
        "name": "get_best_route",
        "description": "Get the optimal current route to the next delivery with traffic data",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "type": "function",
        "name": "start_navigation",
        "description": "Open Google Maps navigation to the next delivery",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "type": "function",
        "name": "call_customer",
        "description": "Initiate a phone call to the customer via LiveKit SIP",
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
        "type": "function",
        "name": "notify_customer",
        "description": "Send an SMS notification to the customer",
        "parameters": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                    "description": "Message content to send"
                }
            },
            "required": ["message"]
        }
    },
    {
        "type": "function",
        "name": "get_next_order",
        "description": "Get the next order from the company queue",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "type": "function",
        "name": "get_shift_summary",
        "description": "Get current shift progress statistics",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "type": "function",
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


def get_tools() -> List[Dict[str, Any]]:
    """Get the list of available tools for the agent."""
    return TOOLS


def get_tool_by_name(tool_name: str) -> Dict[str, Any]:
    """Get a specific tool by name."""
    for tool in TOOLS:
        if tool.get("name") == tool_name:
            return tool
    return None