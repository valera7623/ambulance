"""Write the bundled mobile snapshot from the seed database."""

from __future__ import annotations

import json
from pathlib import Path

from smp_api.seed_db import build_seed_database
from smp_api.snapshot import build_snapshot, connect_readonly

API_ROOT = Path(__file__).resolve().parents[1]
SEED = API_ROOT / "data" / "seed_clinical.json"
DB = API_ROOT / "data" / "content.db"
ASSET = API_ROOT.parent / "app" / "assets" / "snapshot.json"


def export_bundled_snapshot(asset_path: Path = ASSET, db_path: Path = DB) -> dict:
    build_seed_database(db_path, SEED)
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
    return snapshot


if __name__ == "__main__":
    exported = export_bundled_snapshot()
    print(exported["fingerprint"], "diagnoses", len(exported["diagnoses"]))
