import asyncio
from typing import Dict, Any, List
from app.agents.tools import delivery, navigation, communication


class ToolOrchestrator:
    """
    Orchestrates parallel tool execution for the voice agent.
    Uses asyncio.gather() to execute multiple tools simultaneously.
    """
    
    def __init__(self):
        # Registry mapping tool names to their handler functions
        self.TOOL_REGISTRY = {
            # Delivery tools
            "get_next_delivery": delivery.get_next_delivery,
            "update_delivery_status": delivery.update_delivery_status,
            "log_exception": delivery.log_exception,
            "get_next_order": delivery.get_next_order,
            
            # Navigation tools
            "get_best_route": navigation.get_best_route,
            "start_navigation": navigation.start_navigation,
            
            # Communication tools
            "call_customer": communication.call_customer,
            "notify_customer": communication.notify_customer,
            "alert_dispatcher": communication.alert_dispatcher,
            
            # Shift tools
            "get_shift_summary": delivery.get_shift_summary,
        }
    
    async def execute_parallel(self, tool_calls: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Execute multiple tool calls in parallel using asyncio.gather().
        
        Args:
            tool_calls: List of tool call dicts with 'name', 'parameters', 'tool_call_id'
            
        Returns:
            List of results with 'tool_call_id' and 'output'
        """
        tasks = []
        for tool_call in tool_calls:
            task = self._execute_single(tool_call)
            tasks.append(task)
        
        # Execute all tools in parallel, return_exceptions=True prevents one failure from stopping all
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Format results
        formatted_results = []
        for i, result in enumerate(results):
            tool_call_id = tool_calls[i].get("tool_call_id", "")
            
            if isinstance(result, Exception):
                formatted_results.append({
                    "tool_call_id": tool_call_id,
                    "output": {"error": str(result)}
                })
            else:
                formatted_results.append({
                    "tool_call_id": tool_call_id,
                    "output": result
                })
        
        return formatted_results
    
    async def execute_single(
        self,
        tool_name: str,
        parameters: Dict[str, Any],
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Execute a single tool call.
        
        Args:
            tool_name: Name of the tool to execute
            parameters: Tool parameters
            context: Context dict with driver_id, shift_id, session_id
            
        Returns:
            Tool result dict
        """
        if tool_name not in self.TOOL_REGISTRY:
            return {"error": f"Unknown tool: {tool_name}"}
        
        handler = self.TOOL_REGISTRY[tool_name]
        
        try:
            # Call the tool handler with parameters and context
            result = await handler(parameters, context)
            return result
        except Exception as e:
            return {"error": str(e)}
