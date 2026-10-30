"""Same stable key as the Telegram bot's medical_ingest.make_stable_key."""

from __future__ import annotations

import hashlib

def make_stable_key(department_slug: str | None, display_code: str | None, title: str) -> str:
    """sha256 of '{slug}|{code}|{title}' after the bot's strip/lower rules."""
    raw = (
        f"{(department_slug or 'therapy').strip().lower()}|"
        f"{(display_code or '').strip().lower()}|"
        f"{title.strip().lower()[:500]}"
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()
