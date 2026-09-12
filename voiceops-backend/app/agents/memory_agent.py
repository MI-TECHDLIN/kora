"""
Memory Agent
Provides persistent long-term memory for drivers, delivery locations, and recurring customers.
Stores actionable operational observations (e.g. gate codes, delivery quirks, parking spots).
"""
import logging
from typing import List, Dict, Any, Optional
from datetime import datetime, timezone
from app.db.queries import get_supabase, is_valid_uuid

logger = logging.getLogger(__name__)


class MemoryAgent:
    def _is_worth_storing(self, content: str, confidence: float) -> bool:
        """Filter out low-confidence or trivial noise."""
        return confidence >= 0.6 and len(content.strip()) >= 5

    async def store(
        self,
        entity_type: str,
        entity_id: str,
        memory_type: str,
        content: str,
        confidence: float = 0.8,
        source: str = "voice_agent",
    ) -> Dict[str, Any]:
        """
        Stores an observation in the memories table.
        """
        if not self._is_worth_storing(content, confidence):
            return {}

        now = datetime.now(timezone.utc).isoformat()
        try:
            row = {
                "entity_type": entity_type.upper(),
                "entity_id": str(entity_id),
                "memory_type": memory_type,
                "content": content,
                "confidence": confidence,
                "source": source,
                "created_at": now,
                "last_used_at": now,
            }
            res = get_supabase().table("memories").insert(row).execute()
            return res.data[0] if res.data else {}
        except Exception as e:
            logger.warning(f"[MemoryAgent] Failed to store memory: {e}")
            return {"content": content, "stored": False}

    async def recall(
        self,
        entity_type: str,
        entity_id: str,
        limit: int = 5,
    ) -> List[Dict[str, Any]]:
        """
        Retrieves relevant memories for an entity, updating last_used_at.
        """
        try:
            res = (
                get_supabase().table("memories")
                .select("*")
                .eq("entity_type", entity_type.upper())
                .eq("entity_id", str(entity_id))
                .order("last_used_at", desc=True)
                .limit(limit)
                .execute()
            )
            memories = res.data or []

            # Update last_used_at for retrieved memories
            if memories:
                now = datetime.now(timezone.utc).isoformat()
                for mem in memories:
                    if mem.get("id"):
                        try:
                            get_supabase().table("memories").update({"last_used_at": now}).eq("id", mem["id"]).execute()
                        except Exception:
                            pass

            return memories
        except Exception as e:
            logger.warning(f"[MemoryAgent] Failed to recall memories: {e}")
            return []

    async def inject_into_context(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """
        Enriches voice agent context with location and customer memories.
        """
        current_del = context.get("current_delivery") or {}
        address = current_del.get("address", "")
        customer_phone = current_del.get("customer_phone", "")

        memories: List[str] = []

        if address:
            loc_mem = await self.recall("LOCATION", address, limit=3)
            for m in loc_mem:
                memories.append(f"Location note: {m.get('content')}")

        if customer_phone:
            cust_mem = await self.recall("CUSTOMER", customer_phone, limit=2)
            for m in cust_mem:
                memories.append(f"Customer preference: {m.get('content')}")

        if memories:
            context["contextual_memories"] = memories
            logger.info(f"[MemoryAgent] Enriched context with {len(memories)} memories.")

        return context


memory_agent = MemoryAgent()
