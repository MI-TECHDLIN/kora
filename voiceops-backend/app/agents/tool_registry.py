"""
VoiceOps Tool Registry
Contains the voice tools exposed to AssemblyAI.
"""
import logging
from typing import Dict, Any, List

logger = logging.getLogger(__name__)
from app.agents.tools.delivery import (
    get_next_delivery,
    update_delivery_status,
    log_exception,
    get_next_order,
    accept_order,
    decline_order,
    get_shift_summary
)
from app.agents.tools.navigation import (
    APP_SCREENS,
    get_best_route,
    start_navigation,
    accept_reroute,
    show_screen,
    end_conversation
)

from app.agents.tools.communication import (
    call_customer,
    notify_customer,
    alert_dispatcher
)
from app.agents.tools.preferences import (
    get_preferences,
    set_preference,
    clear_preference,
    reset_preferences
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
            "description": "Start navigation to delivery location. The route is drawn on the driver's in-app map. Trigger phrases: 'navigate', 'take me there', 'get directions'",
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
            "name": "accept_reroute",
            "description": "Accept a suggested reroute and set it as the active navigation route. Trigger phrases: 'yes take that route', 'accept reroute', 'use the alternate route'",
            "parameters": {
                "type": "object",
                "properties": {
                    "eta_minutes": {
                        "type": "number",
                        "description": "ETA of the suggested route in minutes"
                    },
                    "geometry": {
                        "type": "string",
                        "description": "Route geometry/polyline"
                    },
                    "delivery_id": {
                        "type": "string",
                        "description": "Delivery ID for the route"
                    }
                },
                "required": []
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
            "description": "Get the next new order waiting for a driver: the one offered to this driver, else the nearest unassigned one. Trigger phrases: 'next order in queue', 'what's coming after this', 'next job', 'any new orders'",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        },
        {
            "type": "function",
            "name": "accept_order",
            "description": "Accept the new order offered to the driver; it becomes the last stop on their run. Call only after the driver says yes. Trigger phrases: 'yes, I'll take it', 'accept', 'add it to my run'",
            "parameters": {
                "type": "object",
                "properties": {
                    "order_id": {
                        "type": "string",
                        "description": "Order ID. Omit to accept the order currently offered to the driver"
                    }
                },
                "required": []
            }
        },
        {
            "type": "function",
            "name": "decline_order",
            "description": "Decline the new order offered to the driver; it goes to the next nearest driver. Call only after the driver says no. Trigger phrases: 'no', 'pass', 'decline it', 'I can't take it'",
            "parameters": {
                "type": "object",
                "properties": {
                    "order_id": {
                        "type": "string",
                        "description": "Order ID. Omit to decline the order currently offered to the driver"
                    },
                    "reason": {
                        "type": "string",
                        "description": "Why the driver passed, if they said"
                    }
                },
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
        },
        {
            "type": "function",
            "name": "show_screen",
            "description": "Open a screen in the driver's app. Call immediately when the driver explicitly asked to open, show, or go to that screen. When Kora is suggesting the change, ask for voice confirmation and call this tool only after the driver agrees. Do not call it merely because the screen might be useful. map: 'open the map', 'where am I', 'zoom to my location'. settings: 'show my vehicle', 'my profile'. summary: 'show my summary'. voice: 'go home'. Routing tools already open the map, so don't call this alongside them.",
            "parameters": {
                "type": "object",
                "properties": {
                    "screen": {
                        "type": "string",
                        "enum": list(APP_SCREENS),
                        "description": "Screen to open"
                    }
                },
                "required": ["screen"]
            }
        },
        {
            "type": "function",
            "name": "end_conversation",
            "description": "Close the driver's voice conversation when they say they are done. Say a short goodbye first, then call this tool.",
            "parameters": {"type": "object", "properties": {}, "required": []}
        },
        {
            "type": "function",
            "name": "get_preferences",
            "description": "Get all the driver's current preferences. Use when the driver asks to see their settings or preferences.",
            "parameters": {"type": "object", "properties": {}, "required": []}
        },
        {
            "type": "function",
            "name": "set_preference",
            "description": "Set a specific preference for the driver. Use key-value pairs like: auto_accept_orders=true, avoid_highways=true, never_call_customer=true. Key options: auto_accept_orders, auto_decline_orders, max_order_distance_km, avoid_highways, prefer_residential, always_call_before_delivery, never_call_customer, always_send_sms, max_deliveries_per_shift, auto_announce_next_stop, proactive_traffic_alerts.",
            "parameters": {
                "type": "object",
                "properties": {
                    "key": {
                        "type": "string",
                        "description": "The preference key to set"
                    },
                    "value": {
                        "type": "string",
                        "description": "The preference value (use 'true'/'false' for booleans, numbers for numeric values)"
                    }
                },
                "required": ["key", "value"]
            }
        },
        {
            "type": "function",
            "name": "clear_preference",
            "description": "Clear a specific preference for the driver, returning to default behavior for that setting.",
            "parameters": {
                "type": "object",
                "properties": {
                    "key": {
                        "type": "string",
                        "description": "The preference key to clear"
                    }
                },
                "required": ["key"]
            }
        },
        {
            "type": "function",
            "name": "reset_preferences",
            "description": "Reset all preferences to defaults. Use when the driver wants to clear all their custom settings.",
            "parameters": {"type": "object", "properties": {}, "required": []}
        }
    ]


# Tool execution mapping
TOOL_EXECUTORS = {
    "get_next_delivery": get_next_delivery,
    "update_delivery_status": update_delivery_status,
    "log_exception": log_exception,
    "get_best_route": get_best_route,
    "start_navigation": start_navigation,
    "accept_reroute": accept_reroute,
    "call_customer": call_customer,
    "notify_customer": notify_customer,
    "get_next_order": get_next_order,
    "accept_order": accept_order,
    "decline_order": decline_order,
    "get_shift_summary": get_shift_summary,
    "alert_dispatcher": alert_dispatcher,
    "show_screen": show_screen,
    "end_conversation": end_conversation,
    "get_preferences": get_preferences,
    "set_preference": set_preference,
    "clear_preference": clear_preference,
    "reset_preferences": reset_preferences
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
