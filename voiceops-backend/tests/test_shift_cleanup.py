"""Startup/periodic cleanup for abandoned active shifts."""

import asyncio
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock

from app.services import shift_cleanup


def test_sweep_completes_only_shifts_without_recent_activity(monkeypatch):
    now = datetime(2026, 9, 28, 12, tzinfo=timezone.utc)
    close = AsyncMock(return_value=2)
    monkeypatch.setattr(shift_cleanup, "close_inactive_shifts", close)

    result = asyncio.run(shift_cleanup.sweep_stale_shifts(max_age_hours=12, now=now))

    assert result == 2
    assert close.await_args.args == (now - timedelta(hours=12),)


def test_sweep_failure_is_value_free_and_does_not_stop_the_service(monkeypatch, caplog):
    monkeypatch.setattr(
        shift_cleanup, "close_inactive_shifts",
        AsyncMock(side_effect=RuntimeError("sensitive database details")),
    )

    assert asyncio.run(shift_cleanup.sweep_stale_shifts(max_age_hours=12)) == 0
    assert "error_type=RuntimeError" in caplog.text
    assert "sensitive database details" not in caplog.text
