"""Small REST adapters share bounded timeouts and sanitized transport errors."""

import contextvars
import json
import logging
import time
from urllib.parse import urlsplit

import httpx

from app.core.config import get_settings
from app.core.errors import ProviderError

logger = logging.getLogger("insighthub.providers")
# Structured audit of every outbound LLM call: ids and sizes only, never prompts, answers or keys.
audit_logger = logging.getLogger("insighthub.llm_audit")
# Per-request list of (path, gateway call id), filled by post_json and read by the route handler.
llm_calls: contextvars.ContextVar[list | None] = contextvars.ContextVar("llm_calls", default=None)
GATEWAY_ID_HEADER = "x-litellm-call-id"


def post_json(url: str, *, headers: dict, payload: dict) -> dict:
    started = time.perf_counter()
    call_id, outcome = None, "error"
    try:
        # Do not inherit proxies, follow redirects, or log response bodies/URLs.
        with httpx.Client(
            timeout=get_settings().provider_timeout_seconds,
            trust_env=False,
            follow_redirects=False,
        ) as client:
            response = client.post(url, headers=headers, json=payload)
            call_id = response.headers.get(GATEWAY_ID_HEADER)
            response.raise_for_status()
            data = response.json()
            if not isinstance(data, dict):
                raise ValueError("Invalid JSON object")
            outcome = "ok"
            return data
    except (httpx.HTTPError, ValueError):
        logger.warning("AI provider request failed")
        raise ProviderError() from None
    finally:
        path = urlsplit(url).path
        calls = llm_calls.get()
        if calls is not None:
            calls.append((path, call_id))
        audit_logger.info(
            json.dumps(
                {
                    "event": "llm_call",
                    "request_id": call_id,
                    "path": path,
                    "outcome": outcome,
                    "latency_ms": int((time.perf_counter() - started) * 1000),
                }
            )
        )


def token_count(value) -> int | None:
    return value if type(value) is int and value >= 0 else None


def indexed_embeddings(data: dict, count: int) -> list:
    items = data["data"]
    if len(items) != count or any(type(item.get("index")) is not int for item in items):
        raise ProviderError()
    if sorted(item["index"] for item in items) != list(range(count)):
        raise ProviderError()
    return [item["embedding"] for item in sorted(items, key=lambda item: item["index"])]
