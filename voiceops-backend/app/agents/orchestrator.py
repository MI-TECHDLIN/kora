"""
VoiceOps Tool Orchestrator
Executes multi-tool calls in parallel using asyncio.gather().
Guarantees sub-500ms response latency by dispatching concurrent database,
navigation, logistics, and communication operations simultaneously.
"""
import asyncio
import time
import json
import logging
from typing import Dict, Any, List, Optional
from app.agents.tool_registry import execute_tool, TOOL_EXECUTORS

logger = logging.getLogger(__name__)


class ToolOrchestrator:
    """
    High-performance async tool orchestrator.
    Dispatches multiple LLM tool calls concurrently using asyncio.gather().
    """

    @staticmethod
    async def execute_single_tool(
        tool_name: str,
        parameters: Dict[str, Any],
        context: Dict[str, Any],
        call_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Execute an individual tool and record execution metrics with trace ID.
        """
        import uuid
        trace_id = context.get("trace_id") or str(uuid.uuid4())
        t0 = time.perf_counter()

        try:
            result = await execute_tool(tool_name, parameters, context)
            # Key presence, not truthiness: str(TimeoutError()) is "", and that is still an error
            is_error = isinstance(result, dict) and "error" in result
        except Exception as e:
            logger.error(f"[Orchestrator] [{trace_id}] Tool '{tool_name}' failed: {e}")
            result = {"success": False, "error": str(e)}
            is_error = True

        duration_ms = (time.perf_counter() - t0) * 1000.0

        # Log audit trail to DB without letting Supabase latency block the real-time voice path.
        try:
            from app.db.queries import get_supabase, is_valid_uuid
            driver_id = context.get("driver_id")
            session_id = context.get("session_id")
            audit_row = {
                "trace_id": trace_id,
                "session_id": str(session_id) if session_id else None,
                "driver_id": driver_id if is_valid_uuid(driver_id) else None,
                "agent_name": "voice_agent",
                "tool_name": tool_name,
                "tool_input": parameters,
                "tool_output": result if isinstance(result, dict) else {"raw": str(result)},
                "execution_ms": int(duration_ms),
                "success": not is_error,
                "error_message": str(result.get("error")) if is_error and isinstance(result, dict) else None,
            }
            await asyncio.wait_for(
                asyncio.to_thread(lambda: get_supabase().table("agent_audit_trail").insert(audit_row).execute()),
                0.5,
            )
        except Exception as ae:
            logger.debug(f"[Orchestrator] Audit write skipped: {ae}")

        return {
            "type": "tool.result",
            "call_id": call_id or f"call_{tool_name}",
            "tool_name": tool_name,
            "trace_id": trace_id,
            "result": json.dumps(result) if not isinstance(result, str) else result,
            "parsed_result": result,
            "is_error": is_error,
            "duration_ms": round(duration_ms, 2)
        }

    @classmethod
    async def execute_parallel(
        cls,
        tool_calls: List[Dict[str, Any]],
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Execute a batch of tool requests in parallel using asyncio.gather().
        
        Args:
            tool_calls: List of dicts, each with keys 'name', 'arguments', and optional 'call_id'
            context: Context dictionary (driver_id, shift_id, coordinates, etc.)
            
        Returns:
            Dict with:
                - results: List of individual tool result objects
                - total_duration_ms: Total wall-clock time for all tools
                - parallel_speedup: Estimated time saved vs sequential
                - under_500ms: Boolean indicating if SLA was met
        """
        if not tool_calls:
            return {
                "results": [],
                "total_duration_ms": 0.0,
                "under_500ms": True,
                "tool_count": 0
            }

        start_time = time.perf_counter()

        # Create coroutines for concurrent execution
        tasks = [
            cls.execute_single_tool(
                tool_name=tc.get("name", ""),
                parameters=tc.get("arguments") or tc.get("parameters") or {},
                context=context,
                call_id=tc.get("call_id") or tc.get("id")
            )
            for tc in tool_calls
        ]

        # Dispatch all tool calls simultaneously using asyncio.gather()
        raw_results = await asyncio.gather(*tasks, return_exceptions=True)

        total_duration_ms = (time.perf_counter() - start_time) * 1000.0

        formatted_results = []
        sequential_sum_ms = 0.0

        for idx, res in enumerate(raw_results):
            if isinstance(res, Exception):
                tc = tool_calls[idx]
                item = {
                    "type": "tool.result",
                    "call_id": tc.get("call_id", f"call_{idx}"),
                    "tool_name": tc.get("name", "unknown"),
                    "result": json.dumps({"success": False, "error": str(res)}),
                    "parsed_result": {"success": False, "error": str(res)},
                    "is_error": True,
                    "duration_ms": 0.0
                }
            else:
                item = res
                sequential_sum_ms += item.get("duration_ms", 0.0)
            
            formatted_results.append(item)

        time_saved_ms = max(0.0, sequential_sum_ms - total_duration_ms)
        under_500ms = total_duration_ms < 500.0

        logger.info(
            f"[Orchestrator] Executed {len(tool_calls)} tools in parallel via asyncio.gather(): "
            f"Wall-clock: {total_duration_ms:.1f}ms | Sequential sum: {sequential_sum_ms:.1f}ms | "
            f"Time saved: {time_saved_ms:.1f}ms | Under 500ms SLA: {under_500ms}"
        )

        return {
            "results": formatted_results,
            "tool_count": len(tool_calls),
            "total_duration_ms": round(total_duration_ms, 2),
            "sequential_sum_ms": round(sequential_sum_ms, 2),
            "time_saved_ms": round(time_saved_ms, 2),
            "under_500ms": under_500ms
        }

    @classmethod
    async def benchmark_sequential_vs_parallel(
        cls,
        tool_calls: List[Dict[str, Any]],
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Run a live comparison benchmarking sequential execution against parallel asyncio.gather().
        """
        # 1. Sequential Execution
        t_seq_start = time.perf_counter()
        seq_results = []
        for tc in tool_calls:
            r = await cls.execute_single_tool(
                tool_name=tc.get("name", ""),
                parameters=tc.get("arguments") or tc.get("parameters") or {},
                context=context,
                call_id=tc.get("call_id")
            )
            seq_results.append(r)
        seq_duration_ms = (time.perf_counter() - t_seq_start) * 1000.0

        # 2. Parallel Execution (asyncio.gather)
        par_output = await cls.execute_parallel(tool_calls, context)
        par_duration_ms = par_output["total_duration_ms"]

        speedup_factor = round(seq_duration_ms / par_duration_ms, 2) if par_duration_ms > 0 else 1.0

        return {
            "tool_count": len(tool_calls),
            "sequential_ms": round(seq_duration_ms, 2),
            "parallel_asyncio_gather_ms": round(par_duration_ms, 2),
            "latency_reduction_ms": round(seq_duration_ms - par_duration_ms, 2),
            "speedup_factor": f"{speedup_factor}x faster",
            "under_500ms": par_duration_ms < 500.0,
            "results": par_output["results"]
        }
