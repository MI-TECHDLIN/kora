"""
Tests for backend-owned driver-row creation: `POST /v1/driver/ensure-profile`
(docs/contracts/interface.md §2, kora-full-audit report §2.1).

Supabase is an in-memory table store that runs the real queries in
app/db/queries.py, and Supabase Auth is a scripted fake, so these run offline.
"""
import itertools
import uuid
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

DRIVER_ID = "10ed22c4-c1c0-4d37-8683-dbb8f510e4c6"
GOOGLE_TOKEN = "google-token"
# Google sign-in: Supabase Auth user_metadata never has a phone.
GOOGLE_USER = {
    "id": DRIVER_ID,
    "phone": None,
    "user_metadata": {"full_name": "Elena Ramirez"},
}


class FakeQuery:
    """Enough of the PostgREST query builder for app/db/queries.py."""

    def __init__(self, store, table):
        self.store, self.table = store, table
        self.op, self.payload = "select", None
        self.filters = []

    def select(self, columns="*"):
        self.op = "select"
        return self

    def insert(self, row):
        self.op, self.payload = "insert", row
        return self

    def eq(self, column, value):
        self.filters.append(lambda r: r.get(column) == value)
        return self

    def execute(self):
        rows = self.store.tables.setdefault(self.table, [])
        if self.op == "insert":
            if self.store.fail_insert:
                raise RuntimeError("duplicate key value violates unique constraint")
            row = {"id": str(uuid.uuid4()), "created_at": next(self.store.clock), **self.payload}
            rows.append(row)
            return SimpleNamespace(data=[dict(row)])
        matched = [r for r in rows if all(f(r) for f in self.filters)]
        return SimpleNamespace(data=[dict(r) for r in matched])


class FakeStore:
    def __init__(self):
        self.tables = {}
        self.clock = itertools.count(1)
        self.fail_insert = False

    def table(self, name):
        return FakeQuery(self, name)


class FakeAuth:
    def __init__(self, users):
        self._users = users

    def get_user(self, token):
        if token not in self._users:
            raise Exception("invalid JWT")
        user = dict(self._users[token])
        return SimpleNamespace(user=SimpleNamespace(model_dump=lambda: user))


class FakeSupabase:
    def __init__(self, users):
        self.auth = FakeAuth(users)


@pytest.fixture
def store(monkeypatch):
    fake = FakeStore()
    monkeypatch.setattr("app.db.queries.get_supabase", lambda: fake)
    return fake


@pytest.fixture
def auth(monkeypatch):
    users = {GOOGLE_TOKEN: GOOGLE_USER}
    monkeypatch.setattr("app.dependencies.get_supabase_client", lambda: FakeSupabase(users))
    return users


def test_google_sign_in_gets_a_driver_row_without_a_phone(store, auth):
    """Google sign-in has no phone in user_metadata; ensure-profile must still succeed
    now that drivers.phone is nullable, instead of throwing (kora-full-audit §2.1)."""
    response = client.post(
        "/v1/driver/ensure-profile",
        headers={"Authorization": f"Bearer {GOOGLE_TOKEN}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == DRIVER_ID
    assert body["name"] == "Elena Ramirez"
    assert body.get("phone") is None
    assert len(store.tables["drivers"]) == 1


def test_ensure_profile_is_idempotent_and_safe_under_a_race(store, auth):
    """Calling it twice (e.g. a sign-in retry) must not error or create a second row."""
    headers = {"Authorization": f"Bearer {GOOGLE_TOKEN}"}
    first = client.post("/v1/driver/ensure-profile", headers=headers)
    assert first.status_code == 200

    second = client.post("/v1/driver/ensure-profile", headers=headers)
    assert second.status_code == 200
    assert second.json()["id"] == DRIVER_ID
    assert len(store.tables["drivers"]) == 1

    # A losing concurrent insert (another request won the id-PK race) recovers instead
    # of surfacing the database's duplicate-key error to the driver.
    store.tables["drivers"].clear()
    store.fail_insert = True
    store.tables["drivers"].append({"id": DRIVER_ID, "phone": None, "name": "Elena Ramirez"})
    third = client.post("/v1/driver/ensure-profile", headers=headers)
    assert third.status_code == 200
    assert third.json()["id"] == DRIVER_ID


def test_profile_and_shift_recover_once_the_row_exists(store, auth):
    """Profile's GET /v1/driver/profile and Summary's POST /v1/shift/start both depend
    on the drivers row transitively; both must recover once ensure-profile has run."""
    headers = {"Authorization": f"Bearer {GOOGLE_TOKEN}"}

    # Before the row exists: the 404-forever symptom from the audit.
    assert client.get("/v1/driver/profile", headers=headers).status_code == 404

    ensure = client.post("/v1/driver/ensure-profile", headers=headers)
    assert ensure.status_code == 200

    profile = client.get("/v1/driver/profile", headers=headers)
    assert profile.status_code == 200
    assert profile.json()["id"] == DRIVER_ID

    # Summary needs an active shift, which needs the driver row (FK) to exist.
    shift = client.post("/v1/shift/start", headers=headers)
    assert shift.status_code == 200
    assert shift.json()["status"] == "active"
