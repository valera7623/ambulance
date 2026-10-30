"""Master-password login. The token is an HMAC, so the API stores no sessions."""

from __future__ import annotations

import hashlib
import hmac
import time

from fastapi import HTTPException, Request


def issue_token(password: str, ttl_seconds: int, now: float | None = None) -> str:
    expires = int((now if now is not None else time.time()) + ttl_seconds)
    message = str(expires).encode("ascii")
    signature = hmac.new(password.encode("utf-8"), message, hashlib.sha256).hexdigest()
    return f"{expires}.{signature}"


def token_is_valid(token: str, password: str, now: float | None = None) -> bool:
    if not token or "." not in token:
        return False
    expires_text, signature = token.split(".", 1)
    try:
        expires = int(expires_text)
    except ValueError:
        return False
    if expires < int(now if now is not None else time.time()):
        return False
    expected = hmac.new(
        password.encode("utf-8"), expires_text.encode("ascii"), hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


def passwords_match(provided: str, expected: str) -> bool:
    return hmac.compare_digest(
        hashlib.sha256(provided.encode("utf-8")).digest(),
        hashlib.sha256(expected.encode("utf-8")).digest(),
    )


def require_token(request: Request, password: str) -> None:
    header = request.headers.get("authorization", "")
    if not header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing token")
    token = header.split(" ", 1)[1].strip()
    if not token_is_valid(token, password):
        raise HTTPException(status_code=401, detail="invalid token")
