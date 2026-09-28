"""Bounded cleanup for shifts abandoned without an explicit end action."""

import asyncio
from datetime import datetime, timedelta, timezone
import logging
from typing import Optional

from app.config import settings
from app.db.queries import close_inactive_shifts


logger = logging.getLogger(__name__)


async def sweep_stale_shifts(
    *, max_age_hours: Optional[float] = None, now: Optional[datetime] = None,
) -> int:
    """Complete stale active shifts; database errors remain visible but do not stop startup."""
    max_age = settings.stale_shift_max_age_hours if max_age_hours is None else max_age_hours
    current = now or datetime.now(timezone.utc)
    try:
        cutoff = current - timedelta(hours=max_age)
        count = await asyncio.wait_for(
            asyncio.to_thread(lambda: asyncio.run(close_inactive_shifts(cutoff))),
            timeout=settings.stale_shift_sweep_timeout_seconds,
        )
    except Exception as exc:
        logger.warning("[ShiftCleanup] sweep failed error_type=%s", type(exc).__name__)
        return 0
    if count:
        logger.info("[ShiftCleanup] completed stale shifts count=%d", count)
    return count


async def run_stale_shift_sweeper() -> None:
    """Run immediately at startup and periodically until application shutdown."""
    while True:
        await sweep_stale_shifts()
        await asyncio.sleep(settings.stale_shift_sweep_interval_seconds)
