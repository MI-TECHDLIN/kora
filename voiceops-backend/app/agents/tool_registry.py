"""
VoiceOps Tool Registry
Contains all 10 tools as specified in the VoiceOps Agent Tools Reference v1.0
"""
from typing import Dict, Any, List
from app.agents.tools.delivery import (
    get_next_delivery,
    update_delivery_status,
    log_exception,
    get_next_order,
    get_shift_summary
)
from app.agents.tools.navigation import (
    get_best_route,
    start_navigation
)
from app.agents.tools.communication import (
    call_customer,
    notify_customer,
    alert_dispatcher
)


def get_tools() -> List[Dict[str, Any]]:
    """
    Return all tools for AssemblyAI Voice Agent configuration.
    Follows the exact tool specification from VoiceOps Agent Tools Reference v1.0
    """
    return [
        {
            "type": "function",
            "name": "get_next_delivery",
            "description": "Get the next delivery in the current shift. Trigger phrases: 'next stop', 'where to?', 'next delivery'",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        },
        {
            "type": "function",
            "name": "update_delivery_status",
            "description": "Update delivery status to delivered, failed, or rescheduled. Trigger phrases: 'mark as delivered', 'done', 'package delivered', 'failed', 'nobody home'",
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "enum": ["delivered", "failed", "rescheduled"],
                        "description": "Delivery status"
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
            "description": "Log a delivery exception with reason and resolution. Trigger phrases: 'failed delivery', 'wrong address', 'gate locked', 'package damaged'",
            "parameters": {
                "type": "object",
                "properties": {
                    "reason": {
                        "type": "string",
                        "enum": ["customer_unavailable", "wrong_address", "access_denied", "damaged", "other"],
                        "description": "Reason for exception"
                    },
                    "resolution": {
                        "type": "string",
                        "enum": ["reschedule", "leave_with_neighbor", "return_to_depot", "await_customer"],
                        "description": "How to resolve the exception"
                    },
                    "notes": {
                        "type": "string",
                        "description": "Additional notes about the exception"
                    }
                },
                "required": ["reason", "resolution"]
            }
        },
        {
            "type": "function",
            "name": "get_best_route",
            "description": "Get the best route with traffic information. Trigger phrases: 'best route', 'any traffic', 'check my route', 'faster way'",
            "parameters": {
                "type": "object",
                "properties": {
                    "delivery_id": {
                        "type": "string",
                        "description": "Delivery ID to get route for"
                    }
                },
                "required": ["delivery_id"]
            }
        },
        {
            "type": "function",
            "name": "start_navigation",
            "description": "Start navigation to delivery location using Google Maps. Trigger phrases: 'navigate', 'take me there', 'get directions'",
            "parameters": {
                "type": "object",
                "properties": {
                    "delivery_id": {
                        "type": "string",
                        "description": "Delivery ID to navigate to"
                    }
                },
                "required": ["delivery_id"]
            }
        },
        {
            "type": "function",
            "name": "call_customer",
            "description": "Call the customer via Twilio. Trigger phrases: 'call the customer', 'ring the customer', 'call them'",
            "parameters": {
                "type": "object",
                "properties": {
                    "delivery_id": {
                        "type": "string",
                        "description": "Delivery ID"
                    },
                    "message": {
                        "type": "string",
                        "description": "Message to communicate when calling"
                    }
                },
                "required": ["delivery_id"]
            }
        },
        {
            "type": "function",
            "name": "notify_customer",
            "description": "Send SMS notification to customer via Twilio. Trigger phrases: 'message the customer', 'tell customer I'm close', 'send ETA', 'I'm 5 minutes away'",
            "parameters": {
                "type": "object",
                "properties": {
                    "delivery_id": {
                        "type": "string",
                        "description": "Delivery ID"
                    },
                    "message_type": {
                        "type": "string",
                        "enum": ["on_my_way", "nearby", "running_late", "missed", "custom"],
                        "description": "Type of message to send"
                    },
                    "custom_message": {
                        "type": "string",
                        "description": "Custom message if message_type is 'custom'"
                    }
                },
                "required": ["delivery_id", "message_type"]
            }
        },
        {
            "type": "function",
            "name": "get_next_order",
            "description": "Get the next order in the queue from Onfleet. Trigger phrases: 'next order in queue', 'what's coming after this', 'next job'",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        },
        {
            "type": "function",
            "name": "get_shift_summary",
            "description": "Get shift statistics and progress. Trigger phrases: 'how am I doing', 'how many left', 'my progress', 'shift summary'",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        },
        {
            "type": "function",
            "name": "alert_dispatcher",
            "description": "Alert dispatcher with priority message. Trigger phrases: 'alert the dispatcher', 'contact dispatch', 'I need help'",
            "parameters": {
                "type": "object",
                "properties": {
                    "delivery_id": {
                        "type": "string",
                        "description": "Delivery ID (optional)"
                    },
                    "message": {
                        "type": "string",
                        "description": "Message to send to dispatcher"
                    },
                    "priority": {
                        "type": "string",
                        "enum": ["normal", "urgent"],
                        "description": "Priority level"
                    }
                },
                "required": ["message", "priority"]
            }
        }
    ]


# Tool execution mapping
TOOL_EXECUTORS = {
    "get_next_delivery": get_next_delivery,
    "update_delivery_status": update_delivery_status,
    "log_exception": log_exception,
    "get_best_route": get_best_route,
    "start_navigation": start_navigation,
    "call_customer": call_customer,
    "notify_customer": notify_customer,
    "get_next_order": get_next_order,
    "get_shift_summary": get_shift_summary,
    "alert_dispatcher": alert_dispatcher
}


async def execute_tool(tool_name: str, parameters: dict, context: dict) -> dict:
    """
    Execute a tool by name with given parameters and context.
    
    Args:
        tool_name: Name of the tool to execute
        parameters: Tool parameters from AssemblyAI
        context: Driver and session context
    
    Returns:
        Tool result dict (JSON-stringified)
    """
    executor = TOOL_EXECUTORS.get(tool_name)
    
    if not executor:
        return {
            "success": False,
            "error": f"Tool '{tool_name}' not found"
        }
    # Safety & authorization check
    from app.agents.tool_safety import tool_safety_gate
    allowed, rejection_reason = await tool_safety_gate.check(tool_name, parameters, context)
    if not allowed:
        return {
            "success": False,
            "error": rejection_reason,
            "blocked_by": "safety_gate"
        }

    try:
        result = await executor(parameters, context)
        return result
    except Exception as e:
        # Never raise unhandled exceptions
        return {
            "success": False,
            "error": str(e)
        }