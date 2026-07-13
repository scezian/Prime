"""
Token auth. Every route depends on verify_token — no exceptions,
even for requests arriving over the tailnet.
"""
from fastapi import Header, HTTPException

from app.config import get_or_create_token

_TOKEN = get_or_create_token()


def verify_token(x_auth_token: str = Header(default="")) -> None:
    if not x_auth_token or x_auth_token != _TOKEN:
        raise HTTPException(status_code=401, detail="Invalid or missing token")
