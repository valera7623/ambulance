import hashlib
import json
import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from smp_api.app import Settings, create_app
from smp_api.auth import issue_token, token_is_valid
from smp_api.seed_db import build_seed_database, medication_names, seed_fingerprint
from smp_api.snapshot import build_snapshot, connect_readonly
from smp_api.stable_key import make_stable_key

SEED = Path(__file__).resolve().parents[1] / "data" / "seed_clinical.json"
SCHEMA = json.loads(
    (Path(__file__).resolve().parents[2] / "contract" / "snapshot.schema.json").read_text(
        encoding="utf-8"
    )
)


def test_stable_key_matches_bot_formula():
    raw = "therapy|i21|" + "оим".strip().lower()
    assert make_stable_key(" Therapy ", "I21", "ОИМ") == hashlib.sha256(
        raw.encode("utf-8")
    ).hexdigest()
    assert make_stable_key("", None, "x") == make_stable_key("therapy", "", "x")
    long_title = "А" * 600
    assert make_stable_key("cardiology", "I10", long_title) == hashlib.sha256(
        f"cardiology|i10|{'а' * 500}".encode("utf-8")
    ).hexdigest()


def test_medication_names_from_mnn():
    names = medication_names(
        "MgSO4 — magnesium sulfate; methyldopa; nifedipine (по показаниям и регистрации)"
    )
    assert names == ["magnesium sulfate", "methyldopa", "nifedipine"]


def test_seed_snapshot_contract(tmp_path: Path):
    db_path = tmp_path / "clinical.db"
    build_seed_database(db_path, SEED)
    before = db_path.read_bytes()
    connection = connect_readonly(db_path)
    try:
        snapshot = build_snapshot(connection)
    finally:
        connection.close()
    assert db_path.read_bytes() == before
    assert snapshot["fingerprint"] == seed_fingerprint(SEED)
    assert snapshot["format_version"] == SCHEMA["properties"]["format_version"]["const"]
    for field in SCHEMA["required"]:
        assert field in snapshot
    assert len(snapshot["departments"]) == 15
    slugs = [row["slug"] for row in snapshot["departments"]]
    assert slugs[0] == "cardiology"
    assert "shock_coma" in slugs
    assert "neonatal_resuscitation" in slugs
    o14 = next(row for row in snapshot["diagnoses"] if row["display_code"] == "O14")
    assert o14["stable_key"] == make_stable_key("gynecology", "O14", o14["title"])
    assert o14["include_in_shock_coma"] is False
    subs = [row for row in snapshot["subconditions"] if row["diagnosis_id"] == o14["id"]]
    assert [row["code_label"] for row in subs] == ["1", "2"]
    assert any(row["name_normalized"] == "methyldopa" for row in snapshot["medications"])
    assert "users" not in snapshot


def test_missing_stable_key_is_filled_only_in_snapshot(tmp_path: Path):
    db_path = tmp_path / "clinical.db"
    build_seed_database(db_path, SEED)
    writable = sqlite3.connect(db_path)
    writable.execute("UPDATE diagnoses SET stable_key = NULL WHERE display_code = 'O15'")
    writable.commit()
    writable.close()
    connection = connect_readonly(db_path)
    try:
        snapshot = build_snapshot(connection)
    finally:
        connection.close()
    o15 = next(row for row in snapshot["diagnoses"] if row["display_code"] == "O15")
    assert o15["stable_key"] == make_stable_key("gynecology", "O15", o15["title"])
    check = sqlite3.connect(f"file:{db_path.resolve().as_posix()}?mode=ro", uri=True)
    stored = check.execute(
        "SELECT stable_key FROM diagnoses WHERE display_code = 'O15'"
    ).fetchone()[0]
    check.close()
    assert stored is None


def test_api_login_and_snapshot(tmp_path: Path):
    db_path = tmp_path / "clinical.db"
    build_seed_database(db_path, SEED)
    settings = Settings(
        sqlite_path=db_path,
        master_password="station-secret",
        token_ttl_seconds=60,
        own_database=False,
    )
    client = TestClient(create_app(settings))
    assert client.get("/v1/content/manifest").status_code == 401
    assert client.post("/v1/auth/login", json={"password": "no"}).status_code == 401
    login = client.post("/v1/auth/login", json={"password": "station-secret"})
    assert login.status_code == 200
    token = login.json()["token"]
    assert token_is_valid(token, "station-secret")
    headers = {"Authorization": f"Bearer {token}"}
    manifest = client.get("/v1/content/manifest", headers=headers)
    assert manifest.status_code == 200
    body = manifest.json()
    assert body["counts"]["diagnoses"] == 8
    assert body["counts"]["departments"] == 15
    snapshot = client.get("/v1/content/snapshot", headers=headers)
    assert snapshot.status_code == 200
    assert snapshot.json()["fingerprint"] == body["fingerprint"]
    assert "password_hash" not in snapshot.text
    expired = issue_token("station-secret", ttl_seconds=-10)
    assert client.get(
        "/v1/content/manifest", headers={"Authorization": f"Bearer {expired}"}
    ).status_code == 401


def test_custom_path_is_not_created(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    missing = tmp_path / "missing.db"
    monkeypatch.setenv("CONTENT_MASTER_PASSWORD", "secret")
    monkeypatch.setenv("SQLITE_PATH", str(missing))
    from smp_api.app import Settings, prepare_database

    settings = Settings.from_env()
    with pytest.raises(SystemExit):
        prepare_database(settings)
    assert not missing.exists()
