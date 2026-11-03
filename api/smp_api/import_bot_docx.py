"""Build the mobile snapshot from the Telegram bot's DOCX protocols."""

from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import types
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
if "smp_api" not in sys.modules:
    package = types.ModuleType("smp_api")
    package.__path__ = [str(Path(__file__).resolve().parent)]
    sys.modules["smp_api"] = package

from smp_api.export_bundled import ASSET
from smp_api.seed_db import build_seed_database
from smp_api.snapshot import build_snapshot, connect_readonly
from smp_api.stable_key import make_stable_key

DEFAULT_BOT = Path("/home/ubuntu/my_telegram_bot")


def _document_to_items(doc) -> list[dict]:
    items: list[dict] = []
    for diagnosis in doc.diagnoses:
        items.append(
            {
                "department_slug": doc.department_slug,
                "display_code": diagnosis.display_code,
                "title": diagnosis.title,
                "conditions_note": diagnosis.conditions_note,
                "branch_prompt": diagnosis.branch_prompt,
                "mnn_hints": diagnosis.mnn_hints,
                "is_emergency": bool(diagnosis.is_emergency),
                "care_volume": diagnosis.care_volume,
                "tactic": diagnosis.tactic,
                "subconditions": [
                    {
                        "code_label": sub.code_label,
                        "title": sub.title,
                        "conditions_detail": sub.conditions_detail,
                        "care_volume": sub.care_volume,
                        "tactic": sub.tactic,
                    }
                    for sub in diagnosis.subconditions
                ],
                "source_file": doc.filename,
                "list_sort_tail": bool(getattr(diagnosis, "list_sort_tail", False)),
            }
        )
    return items


def _dedupe(items: list[dict]) -> list[dict]:
    by_key: dict[str, dict] = {}
    order: list[str] = []
    for item in items:
        slug = str(item.get("department_slug") or "therapy").strip() or "therapy"
        title = str(item.get("title") or "Без названия")
        code = item.get("display_code") or item.get("code")
        key = make_stable_key(slug, None if code is None else str(code), title)
        if key not in by_key:
            order.append(key)
        by_key[key] = item
    return [by_key[key] for key in order]


def collect(bot_root: Path) -> tuple[list[dict], dict[str, tuple[str | None, str | None, str | None]]]:
    sys.path.insert(0, str(bot_root))
    from src.services.department_registry import DEPARTMENT_SEED, slug_from_filename
    from src.services.docx_parser import parse_medical_docx

    known = {slug for slug, _title in DEPARTMENT_SEED}
    data_dir = bot_root / "data"
    paths = sorted(
        path.resolve()
        for path in data_dir.rglob("*.docx")
        if path.is_file() and not path.name.startswith("~$")
    )
    if not paths:
        raise SystemExit(f"No DOCX protocols in {data_dir}")

    items: list[dict] = []
    labels: dict[str, tuple[str | None, str | None, str | None]] = {}
    for path in paths:
        slug = slug_from_filename(path.name)
        if slug not in known:
            slug = "therapy"
        parsed = parse_medical_docx(path, slug)
        chunk = _document_to_items(parsed)
        print(f"{path.name}: {len(chunk)}")
        if parsed.card_label_diagnosis or parsed.card_label_care or parsed.card_label_tactic:
            labels[slug] = (
                parsed.card_label_diagnosis,
                parsed.card_label_care,
                parsed.card_label_tactic,
            )
        items.extend(chunk)
    return _dedupe(items), labels


def apply_labels(db_path: Path, labels: dict[str, tuple[str | None, str | None, str | None]]) -> None:
    connection = sqlite3.connect(db_path)
    try:
        for slug, (diagnosis, care, tactic) in labels.items():
            connection.execute(
                """
                UPDATE medical_departments
                SET card_label_diagnosis = ?, card_label_care = ?, card_label_tactic = ?
                WHERE slug = ?
                """,
                (diagnosis, care, tactic, slug),
            )
        connection.commit()
    finally:
        connection.close()


def export_bot_snapshot(bot_root: Path = DEFAULT_BOT, asset_path: Path = ASSET) -> dict:
    items, labels = collect(bot_root)
    by_slug: dict[str, int] = {}
    with_text = 0
    for item in items:
        slug = str(item.get("department_slug") or "therapy")
        by_slug[slug] = by_slug.get(slug, 0) + 1
        care = str(item.get("care_volume") or "")
        tactic = str(item.get("tactic") or "")
        subs = item.get("subconditions") or []
        sub_text = any(
            str(sub.get("care_volume") or "").strip() or str(sub.get("tactic") or "").strip()
            for sub in subs
        )
        if care.strip() or tactic.strip() or sub_text:
            with_text += 1
    print("diagnoses", len(items), "with recommendation text", with_text)
    for slug, count in sorted(by_slug.items()):
        print(f"  {count:4} {slug}")

    from src.services.department_registry import DEPARTMENT_SEED

    missing = [slug for slug, _title in DEPARTMENT_SEED if by_slug.get(slug, 0) == 0]
    if missing:
        raise SystemExit("Sections without protocols: " + ", ".join(missing))

    with tempfile.TemporaryDirectory() as tmp:
        seed_path = Path(tmp) / "protocols.json"
        db_path = Path(tmp) / "content.db"
        seed_path.write_text(json.dumps(items, ensure_ascii=False), encoding="utf-8")
        build_seed_database(db_path, seed_path)
        apply_labels(db_path, labels)
        connection = connect_readonly(db_path)
        try:
            snapshot = build_snapshot(connection)
        finally:
            connection.close()
    asset_path.parent.mkdir(parents=True, exist_ok=True)
    asset_path.write_text(
        json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("wrote", asset_path, "fingerprint", snapshot["fingerprint"])
    return snapshot


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_BOT
    export_bot_snapshot(root)
