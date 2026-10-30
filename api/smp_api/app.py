"""Read-only content API. It sits beside the bot and opens the same SQLite file."""

from __future__ import annotations

import os
import sqlite3
from dataclasses import dataclass
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.gzip import GZipMiddleware
from pydantic import BaseModel

from smp_api.auth import issue_token, passwords_match, require_token
from smp_api.seed_db import build_seed_database
from smp_api.snapshot import ClinicalDatabaseError, build_snapshot, connect_readonly

PACKAGE_ROOT = Path(__file__).resolve().parent
API_ROOT = PACKAGE_ROOT.parent
DEFAULT_SQLITE = API_ROOT / "data" / "content.db"
DEFAULT_SEED = API_ROOT / "data" / "seed_clinical.json"


@dataclass(frozen=True)
class Settings:
    sqlite_path: Path
    master_password: str
    token_ttl_seconds: int = 30 * 24 * 3600
    host: str = "0.0.0.0"
    port: int = 8080
    own_database: bool = False

    @classmethod
    def from_env(cls) -> "Settings":
        password = os.environ.get("CONTENT_MASTER_PASSWORD", "")
        if not password:
            raise SystemExit("CONTENT_MASTER_PASSWORD is required")
        configured = os.environ.get("SQLITE_PATH", "").strip()
        if configured:
            path = Path(configured)
            own = False
        else:
            path = DEFAULT_SQLITE
            own = True
        return cls(
            sqlite_path=path,
            master_password=password,
            token_ttl_seconds=int(os.environ.get("CONTENT_TOKEN_TTL", str(30 * 24 * 3600))),
            host=os.environ.get("CONTENT_HOST", "0.0.0.0"),
            port=int(os.environ.get("CONTENT_PORT", "8080")),
            own_database=own,
        )


class LoginBody(BaseModel):
    password: str


def prepare_database(settings: Settings) -> None:
    """Create the demo database only when SQLITE_PATH is unset. Never touch the bot file."""
    if settings.sqlite_path.exists():
        return
    if not settings.own_database:
        raise SystemExit(f"Clinical database not found: {settings.sqlite_path}")
    build_seed_database(settings.sqlite_path, DEFAULT_SEED)


def create_app(settings: Settings) -> FastAPI:
    app = FastAPI(title="SMP content API", docs_url=None, redoc_url=None)
    app.add_middleware(GZipMiddleware, minimum_size=500)
    app.state.settings = settings

    @app.post("/v1/auth/login")
    def login(body: LoginBody) -> dict[str, str]:
        if not passwords_match(body.password, settings.master_password):
            raise HTTPException(status_code=401, detail="wrong password")
        return {"token": issue_token(settings.master_password, settings.token_ttl_seconds)}

    @app.get("/v1/content/manifest")
    def manifest(request: Request) -> dict:
        require_token(request, settings.master_password)
        snapshot = _read_snapshot(settings)
        return {
            "format_version": snapshot["format_version"],
            "fingerprint": snapshot["fingerprint"],
            "exported_at": snapshot["exported_at"],
            "counts": {
                "departments": len(snapshot["departments"]),
                "diagnoses": len(snapshot["diagnoses"]),
                "subconditions": len(snapshot["subconditions"]),
                "medications": len(snapshot["medications"]),
            },
        }

    @app.get("/v1/content/snapshot")
    def snapshot(request: Request) -> dict:
        require_token(request, settings.master_password)
        return _read_snapshot(settings)

    return app


def _read_snapshot(settings: Settings) -> dict:
    if not settings.sqlite_path.is_file():
        raise HTTPException(status_code=503, detail="clinical database is missing")
    try:
        connection = connect_readonly(settings.sqlite_path)
    except sqlite3.Error as exc:
        raise HTTPException(status_code=503, detail="cannot open clinical database") from exc
    try:
        try:
            return build_snapshot(connection)
        except ClinicalDatabaseError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
    finally:
        connection.close()


def main() -> None:
    import uvicorn

    settings = Settings.from_env()
    prepare_database(settings)
    uvicorn.run(create_app(settings), host=settings.host, port=settings.port)


if __name__ == "__main__":
    main()
