"""Slack request signing (HMAC-SHA256 over the raw body) with replay defence."""
from __future__ import annotations

import hashlib
import hmac
import time


class SignatureError(Exception):
    """Raised with a short machine reason; never carries the request contents."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def verify_signature(secret: str, timestamp: str | None, signature: str | None, body: bytes,
                     now: float | None = None, window_seconds: int = 300) -> None:
    if not secret:
        raise SignatureError("not_configured")
    if not timestamp or not signature:
        raise SignatureError("missing_headers")
    if not (timestamp.isascii() and timestamp.isdigit()):
        raise SignatureError("bad_timestamp")
    current = time.time() if now is None else now
    if abs(current - int(timestamp)) > window_seconds:
        raise SignatureError("stale_timestamp")
    base = b"v0:" + timestamp.encode() + b":" + body
    expected = "v0=" + hmac.new(secret.encode(), base, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected.encode(), signature.encode("utf-8", "replace")):
        raise SignatureError("signature_mismatch")


def sign(secret: str, timestamp: str, body: bytes) -> str:
    """Compute a Slack-style signature (used by tests and local tooling)."""
    base = b"v0:" + timestamp.encode() + b":" + body
    return "v0=" + hmac.new(secret.encode(), base, hashlib.sha256).hexdigest()
