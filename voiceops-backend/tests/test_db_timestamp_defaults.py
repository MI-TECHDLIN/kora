"""Regression coverage for timestamps populated by Supabase defaults."""

import asyncio

from app.db import queries


DRIVER_ID = "11111111-1111-1111-1111-111111111111"
SHIFT_ID = "22222222-2222-2222-2222-222222222222"
SESSION_ID = "33333333-3333-3333-3333-333333333333"


class _Response:
    def __init__(self, data):
        self.data = data


class _FakeSupabase:
    def __init__(self):
        self.table_name = ""
        self.inserts = []

    def table(self, name):
        self.table_name = name
        return self

    def insert(self, payload):
        self.inserts.append((self.table_name, payload))
        return self

    def execute(self):
        if self.table_name == "shifts":
            return _Response([{"id": SHIFT_ID, "status": "active"}])
        return _Response([{"id": SESSION_ID}])


def test_shift_and_voice_session_inserts_use_database_timestamp_defaults(monkeypatch):
    fake = _FakeSupabase()
    monkeypatch.setattr(queries, "get_supabase", lambda: fake)

    shift = asyncio.run(queries.create_shift(DRIVER_ID))
    session_id = asyncio.run(queries.create_voice_session(SHIFT_ID, DRIVER_ID))

    assert shift["id"] == SHIFT_ID
    assert session_id == SESSION_ID
    assert fake.inserts == [
        ("shifts", {"driver_id": DRIVER_ID, "status": "active"}),
        (
            "voice_sessions",
            {
                "shift_id": SHIFT_ID,
                "driver_id": DRIVER_ID,
                "delivery_id": None,
            },
        ),
    ]
