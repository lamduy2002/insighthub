"""Durable job queue + event dedup on SQLite (WAL). Survives restarts; retries are bounded."""
from __future__ import annotations

import json
import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Job:
    event_id: str
    payload: dict[str, Any]
    attempts: int


class JobStore:
    def __init__(self, path: Path) -> None:
        path = Path(path)
        if str(path) != ":memory:":
            path.parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(str(path), check_same_thread=False, isolation_level=None)
        self._lock = threading.Lock()
        with self._lock:
            self._db.execute("PRAGMA journal_mode=WAL")
            self._db.execute("PRAGMA synchronous=FULL")
            self._db.execute(
                "CREATE TABLE IF NOT EXISTS jobs ("
                "event_id TEXT PRIMARY KEY, payload TEXT NOT NULL, status TEXT NOT NULL, "
                "attempts INTEGER NOT NULL DEFAULT 0, next_at REAL NOT NULL, "
                "created_at REAL NOT NULL, last_error TEXT)")
            # Work interrupted by a crash goes back to the queue.
            self._db.execute("UPDATE jobs SET status='pending' WHERE status='running'")

    def enqueue(self, event_id: str, payload: dict[str, Any], now: float | None = None) -> bool:
        """Insert once per Slack event_id. False means duplicate (already seen, in any state)."""
        stamp = time.time() if now is None else now
        with self._lock:
            cur = self._db.execute(
                "INSERT OR IGNORE INTO jobs(event_id,payload,status,attempts,next_at,created_at) "
                "VALUES (?,?,'pending',0,?,?)", (event_id, json.dumps(payload), stamp, stamp))
            return cur.rowcount == 1

    def claim(self, now: float | None = None) -> Job | None:
        stamp = time.time() if now is None else now
        with self._lock:
            row = self._db.execute(
                "SELECT event_id,payload,attempts FROM jobs WHERE status='pending' AND next_at<=? "
                "ORDER BY created_at LIMIT 1", (stamp,)).fetchone()
            if row is None:
                return None
            self._db.execute("UPDATE jobs SET status='running' WHERE event_id=?", (row[0],))
            return Job(row[0], json.loads(row[1]), row[2])

    def complete(self, event_id: str) -> None:
        with self._lock:
            self._db.execute("UPDATE jobs SET status='done' WHERE event_id=?", (event_id,))

    def fail(self, event_id: str, error: str, max_attempts: int, backoff_base: float,
             now: float | None = None) -> str:
        """Record a failed attempt. Returns 'retry' (exponential backoff) or 'dead'."""
        stamp = time.time() if now is None else now
        with self._lock:
            row = self._db.execute("SELECT attempts FROM jobs WHERE event_id=?", (event_id,)).fetchone()
            attempts = (row[0] if row else 0) + 1
            if attempts >= max_attempts:
                self._db.execute("UPDATE jobs SET status='dead',attempts=?,last_error=? WHERE event_id=?",
                                 (attempts, error[:100], event_id))
                return "dead"
            delay = backoff_base * (2 ** (attempts - 1))
            self._db.execute("UPDATE jobs SET status='pending',attempts=?,next_at=?,last_error=? WHERE event_id=?",
                             (attempts, stamp + delay, error[:100], event_id))
            return "retry"

    def counts(self) -> dict[str, int]:
        with self._lock:
            return dict(self._db.execute("SELECT status,COUNT(*) FROM jobs GROUP BY status").fetchall())

    def close(self) -> None:
        with self._lock:
            self._db.close()
