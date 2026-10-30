"""Read a clinical SQLite file and emit a snapshot. Selects only."""

from __future__ import annotations

import hashlib
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from smp_api.departments import FINGERPRINT_META_KEY
from smp_api.stable_key import make_stable_key

FORMAT_VERSION = 1
CONTENT_TABLES = (
    "medical_departments",
    "diagnoses",
    "diagnosis_subconditions",
    "treatments",
    "tactics",
    "medications",
    "app_meta",
)


class ClinicalDatabaseError(RuntimeError):
    pass


def connect_readonly(path: Path) -> sqlite3.Connection:
    uri = f"file:{path.resolve().as_posix()}?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def _columns(connection: sqlite3.Connection, table: str) -> set[str]:
    rows = connection.execute(f"PRAGMA table_info({table})").fetchall()
    return {row[1] for row in rows}


def _require_tables(connection: sqlite3.Connection) -> None:
    found = {
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        ).fetchall()
    }
    missing = [name for name in ("medical_departments", "diagnoses") if name not in found]
    if missing:
        raise ClinicalDatabaseError(
            "SQLite is not a clinical reference database: missing " + ", ".join(missing)
        )


def _bool(value: Any) -> bool:
    return bool(value)


def _text(value: Any) -> str | None:
    if value is None:
        return None
    return str(value)


def build_snapshot(connection: sqlite3.Connection) -> dict[str, Any]:
    _require_tables(connection)
    departments = _departments(connection)
    slug_by_id = {row["id"]: row["slug"] for row in departments}
    diagnoses = _diagnoses(connection, slug_by_id)
    snapshot = {
        "format_version": FORMAT_VERSION,
        "fingerprint": _fingerprint(connection, diagnoses),
        "exported_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "departments": departments,
        "diagnoses": diagnoses,
        "subconditions": _simple_rows(
            connection,
            "diagnosis_subconditions",
            ("id", "diagnosis_id", "code_label", "title", "conditions_detail", "sort_order"),
        ),
        "treatments": _simple_rows(
            connection,
            "treatments",
            ("id", "diagnosis_id", "subcondition_id", "body"),
            defaults={"body": ""},
        ),
        "tactics": _simple_rows(
            connection,
            "tactics",
            ("id", "diagnosis_id", "subcondition_id", "body"),
            defaults={"body": ""},
        ),
        "medications": _simple_rows(
            connection,
            "medications",
            ("id", "name_normalized", "diagnosis_id", "subcondition_id", "source_hint"),
        ),
    }
    return snapshot


def _departments(connection: sqlite3.Connection) -> list[dict[str, Any]]:
    columns = _columns(connection, "medical_departments")
    order = "ORDER BY sort_order, id" if "sort_order" in columns else "ORDER BY id"
    rows = connection.execute(f"SELECT * FROM medical_departments {order}").fetchall()
    exported: list[dict[str, Any]] = []
    for row in rows:
        exported.append(
            {
                "id": row["id"],
                "slug": row["slug"],
                "title": row["title"],
                "sort_order": row["sort_order"] if "sort_order" in columns else 0,
                "card_label_diagnosis": _text(row["card_label_diagnosis"])
                if "card_label_diagnosis" in columns
                else None,
                "card_label_care": _text(row["card_label_care"])
                if "card_label_care" in columns
                else None,
                "card_label_tactic": _text(row["card_label_tactic"])
                if "card_label_tactic" in columns
                else None,
            }
        )
    return exported


def _diagnoses(
    connection: sqlite3.Connection, slug_by_id: dict[int, str]
) -> list[dict[str, Any]]:
    columns = _columns(connection, "diagnoses")
    if "department_sort_order" in columns:
        order = "ORDER BY department_id, department_sort_order, id"
    else:
        order = "ORDER BY id"
    rows = connection.execute(f"SELECT * FROM diagnoses {order}").fetchall()
    exported: list[dict[str, Any]] = []
    for row in rows:
        data = {key: row[key] for key in row.keys()}
        slug = slug_by_id.get(data["department_id"], "therapy")
        stable = data.get("stable_key") or make_stable_key(
            slug, data.get("display_code"), str(data.get("title") or "")
        )
        exported.append(
            {
                "id": data["id"],
                "stable_key": stable,
                "department_id": data["department_id"],
                "display_code": _text(data.get("display_code")),
                "title": str(data.get("title") or ""),
                "conditions_note": _text(data.get("conditions_note")),
                "branch_prompt": _text(data.get("branch_prompt")),
                "mnn_hints": _text(data.get("mnn_hints")),
                "is_emergency": _bool(data.get("is_emergency")),
                "include_in_shock_coma": _bool(data.get("include_in_shock_coma")),
                "search_blob": str(data.get("search_blob") or ""),
                "source_file": _text(data.get("source_file")),
                "department_sort_order": int(data.get("department_sort_order") or 0)
                if "department_sort_order" in columns
                else 0,
                "ingest_sequence": int(data.get("ingest_sequence") or 0)
                if "ingest_sequence" in columns
                else 0,
                "list_sort_tail": _bool(data.get("list_sort_tail"))
                if "list_sort_tail" in columns
                else False,
            }
        )
    return exported


def _simple_rows(
    connection: sqlite3.Connection,
    table: str,
    fields: tuple[str, ...],
    defaults: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    known = {
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        ).fetchall()
    }
    if table not in known:
        return []
    columns = _columns(connection, table)
    present = [field for field in fields if field in columns or field == "id"]
    if "id" not in columns:
        return []
    rows = connection.execute(f"SELECT * FROM {table} ORDER BY id").fetchall()
    exported: list[dict[str, Any]] = []
    for row in rows:
        item: dict[str, Any] = {}
        for field in fields:
            if field not in present and field not in columns:
                item[field] = None if not defaults or field not in defaults else defaults[field]
                continue
            value = row[field] if field in columns else None
            if field == "body" and value is None:
                value = ""
            item[field] = value
        exported.append(item)
    return exported


def _fingerprint(connection: sqlite3.Connection, diagnoses: list[dict[str, Any]]) -> str:
    if "app_meta" in {
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        ).fetchall()
    }:
        found = connection.execute(
            "SELECT value FROM app_meta WHERE key = ?",
            (FINGERPRINT_META_KEY,),
        ).fetchone()
        if found and found[0]:
            return str(found[0])
    digest = hashlib.sha256()
    for row in sorted(diagnoses, key=lambda item: item["stable_key"]):
        digest.update(row["stable_key"].encode("utf-8"))
        digest.update(b"|")
        digest.update(row["title"].encode("utf-8"))
        digest.update(b"\n")
    return "content:" + digest.hexdigest()
