"""Build a local SQLite file in the bot's clinical shape. Never used on SQLITE_PATH."""

from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path

from smp_api.departments import DEPARTMENT_SEED, FINGERPRINT_META_KEY, SHOCK_SECTION_SLUG
from smp_api.stable_key import make_stable_key

SCHEMA = """
CREATE TABLE medical_departments (
  id INTEGER PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  card_label_diagnosis TEXT,
  card_label_care TEXT,
  card_label_tactic TEXT
);
CREATE TABLE diagnoses (
  id INTEGER PRIMARY KEY,
  stable_key TEXT,
  department_id INTEGER NOT NULL,
  display_code TEXT,
  title TEXT NOT NULL,
  conditions_note TEXT,
  branch_prompt TEXT,
  mnn_hints TEXT,
  is_emergency INTEGER NOT NULL DEFAULT 0,
  include_in_shock_coma INTEGER NOT NULL DEFAULT 0,
  search_blob TEXT NOT NULL DEFAULT '',
  source_file TEXT,
  department_sort_order INTEGER NOT NULL DEFAULT 0,
  ingest_sequence INTEGER NOT NULL DEFAULT 0,
  list_sort_tail INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE diagnosis_subconditions (
  id INTEGER PRIMARY KEY,
  diagnosis_id INTEGER NOT NULL,
  code_label TEXT NOT NULL,
  title TEXT NOT NULL,
  conditions_detail TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE treatments (
  id INTEGER PRIMARY KEY,
  diagnosis_id INTEGER UNIQUE,
  subcondition_id INTEGER UNIQUE,
  body TEXT NOT NULL DEFAULT ''
);
CREATE TABLE tactics (
  id INTEGER PRIMARY KEY,
  diagnosis_id INTEGER UNIQUE,
  subcondition_id INTEGER UNIQUE,
  body TEXT NOT NULL DEFAULT ''
);
CREATE TABLE medications (
  id INTEGER PRIMARY KEY,
  name_normalized TEXT NOT NULL,
  diagnosis_id INTEGER NOT NULL,
  subcondition_id INTEGER,
  source_hint TEXT
);
CREATE TABLE app_meta (
  id INTEGER PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  value TEXT NOT NULL
);
"""


def medication_names(*texts: str | None) -> list[str]:
    """Latin names from MNN hints. Care prose in Russian stays in search_blob."""
    import re

    names: list[str] = []
    seen: set[str] = set()
    for text in texts:
        if not text:
            continue
        for part in re.split(r"[;\n]", text):
            part = re.sub(r"\([^)]*\)", " ", part)
            if "—" in part or "–" in part:
                part = re.split(r"[—–]", part, maxsplit=1)[-1]
            name = " ".join(part.split()).strip(" .,")
            if len(name) < 3 or len(name) > 80:
                continue
            letters = [c for c in name if c.isalpha()]
            if not letters:
                continue
            cyr = sum(1 for c in letters if "а" <= c.lower() <= "я" or c.lower() == "ё")
            if cyr / len(letters) > 0.4:
                continue
            key = name.lower()[:256]
            if key in seen:
                continue
            seen.add(key)
            names.append(key)
    return names


def _search_blob(item: dict, subs: list[dict]) -> str:
    parts = [
        str(item.get("title") or ""),
        str(item.get("display_code") or item.get("code") or ""),
        str(item.get("care_volume") or ""),
        str(item.get("tactic") or ""),
        str(item.get("conditions_note") or ""),
        str(item.get("mnn_hints") or ""),
    ]
    for sub in subs:
        parts.extend(
            [
                str(sub.get("title") or ""),
                str(sub.get("conditions_detail") or ""),
                str(sub.get("care_volume") or ""),
                str(sub.get("tactic") or ""),
            ]
        )
    return " ".join(parts).lower()


def _subs(item: dict) -> list[dict]:
    raw = item.get("subconditions") or item.get("branches") or []
    if not isinstance(raw, list):
        return []
    subs: list[dict] = []
    for index, row in enumerate(raw):
        if not isinstance(row, dict):
            continue
        subs.append(
            {
                "code_label": str(row.get("code_label") or (index + 1))[:32],
                "title": str(row.get("title") or row.get("option_label") or "Условие")[:512],
                "conditions_detail": row.get("conditions_detail"),
                "care_volume": str(row.get("care_volume") or ""),
                "tactic": str(row.get("tactic") or ""),
            }
        )
    return subs


def seed_fingerprint(seed_path: Path) -> str:
    """Matches the bot's bundle_fingerprint([], seed_path)."""
    digest = hashlib.sha256()
    file_digest = hashlib.sha256()
    with seed_path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            file_digest.update(chunk)
    digest.update(b"seed:")
    digest.update(file_digest.hexdigest().encode("ascii"))
    return "bundle:" + digest.hexdigest()


def build_seed_database(db_path: Path, seed_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()
    items = json.loads(seed_path.read_text(encoding="utf-8"))
    if not isinstance(items, list):
        raise ValueError("seed JSON must be a list")

    conn = sqlite3.connect(db_path)
    try:
        conn.executescript(SCHEMA)
        slug_to_id: dict[str, int] = {}
        for index, (slug, title) in enumerate(DEPARTMENT_SEED):
            cursor = conn.execute(
                "INSERT INTO medical_departments (slug, title, sort_order) VALUES (?, ?, ?)",
                (slug, title, index),
            )
            slug_to_id[slug] = int(cursor.lastrowid)

        per_department: dict[int, int] = {}
        ingest_sequence = 0
        for item in items:
            slug = str(item.get("department_slug") or "therapy").strip() or "therapy"
            department_id = slug_to_id.get(slug) or slug_to_id["therapy"]
            subs = _subs(item)
            title = str(item.get("title") or "Без названия")
            code = item.get("display_code") or item.get("code")
            code_text = None if code is None else str(code)
            stable_key = make_stable_key(slug, code_text, title)
            per_department[department_id] = per_department.get(department_id, 0) + 1
            ingest_sequence += 1
            shock = slug == SHOCK_SECTION_SLUG or bool(item.get("include_in_shock_coma", False))
            cursor = conn.execute(
                """
                INSERT INTO diagnoses (
                  stable_key, department_id, display_code, title, conditions_note,
                  branch_prompt, mnn_hints, is_emergency, include_in_shock_coma,
                  search_blob, source_file, department_sort_order, ingest_sequence,
                  list_sort_tail
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    stable_key,
                    department_id,
                    code_text,
                    title[:512],
                    item.get("conditions_note"),
                    item.get("branch_prompt"),
                    item.get("mnn_hints"),
                    1 if item.get("is_emergency") else 0,
                    1 if shock else 0,
                    _search_blob(item, subs),
                    item.get("source_file"),
                    per_department[department_id],
                    ingest_sequence,
                    1 if item.get("list_sort_tail") else 0,
                ),
            )
            diagnosis_id = int(cursor.lastrowid)
            care = str(item.get("care_volume") or "")
            tactic = str(item.get("tactic") or "")
            conn.execute(
                "INSERT INTO treatments (diagnosis_id, body) VALUES (?, ?)",
                (diagnosis_id, care),
            )
            conn.execute(
                "INSERT INTO tactics (diagnosis_id, body) VALUES (?, ?)",
                (diagnosis_id, tactic),
            )
            for sort_order, sub in enumerate(subs):
                sub_cursor = conn.execute(
                    """
                    INSERT INTO diagnosis_subconditions (
                      diagnosis_id, code_label, title, conditions_detail, sort_order
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        diagnosis_id,
                        sub["code_label"],
                        sub["title"],
                        sub["conditions_detail"],
                        sort_order,
                    ),
                )
                sub_id = int(sub_cursor.lastrowid)
                conn.execute(
                    "INSERT INTO treatments (subcondition_id, body) VALUES (?, ?)",
                    (sub_id, sub["care_volume"]),
                )
                conn.execute(
                    "INSERT INTO tactics (subcondition_id, body) VALUES (?, ?)",
                    (sub_id, sub["tactic"]),
                )
            for name in medication_names(item.get("mnn_hints"), care):
                conn.execute(
                    """
                    INSERT INTO medications (name_normalized, diagnosis_id, source_hint)
                    VALUES (?, ?, ?)
                    """,
                    (name, diagnosis_id, name[:500]),
                )
        conn.execute(
            "INSERT INTO app_meta (key, value) VALUES (?, ?)",
            (FINGERPRINT_META_KEY, seed_fingerprint(seed_path)),
        )
        conn.commit()
    finally:
        conn.close()
