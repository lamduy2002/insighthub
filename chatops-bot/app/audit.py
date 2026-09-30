"""Structured audit log: one JSON object per line for every decision and tool call.

Never log secrets, raw provider errors or document content; callers pass short summaries.
"""
from __future__ import annotations

import json
import os
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DECISIONS = {"allowed", "denied", "approval_required"}
_MAX_TEXT = 300


def _clip(value: Any) -> Any:
    if isinstance(value, str):
        return value[:_MAX_TEXT]
    if isinstance(value, dict):
        return {str(k): _clip(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_clip(v) for v in value][:50]
    return value


class AuditLog:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self._lock = threading.Lock()

    def record(self, *, action: str, decision: str, user: str, args: dict[str, Any] | None = None,
               result: str | None = None, reason: str | None = None,
               slack_event_id: str | None = None) -> dict[str, Any]:
        if decision not in DECISIONS:
            raise ValueError("invalid audit decision")
        event: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "event_id": uuid.uuid4().hex,
            "action": action,
            "decision": decision,
            "user": user or "unknown",
        }
        if args:
            event["args"] = _clip(args)
        if result:
            event["result"] = _clip(result)
        if reason:
            event["reason"] = _clip(reason)
        if slack_event_id:
            event["slack_event_id"] = slack_event_id
        run_id = os.environ.get("INSIGHTHUB_VERIFY_RUN_ID")
        if run_id:
            event["test_run_id"] = run_id
        line = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
        with self._lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with self.path.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
        return event

    def read(self) -> list[dict[str, Any]]:
        if not self.path.is_file():
            return []
        return [json.loads(line) for line in self.path.read_text(encoding="utf-8").splitlines() if line.strip()]
