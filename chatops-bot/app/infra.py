"""Infrastructure backends the bot depends on. Real MCP adapters live in mcp_client.py."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol


@dataclass(frozen=True)
class PodInfo:
    name: str
    phase: str
    ready: bool
    restarts: int
    reason: str = ""


class Infra(Protocol):
    async def prom_query(self, expr: str) -> list[dict[str, Any]]:
        """Instant query via the Prometheus MCP server: [{'metric': {...}, 'value': float}]."""

    async def list_pods(self, namespace: str) -> list[PodInfo]:
        """Pods via the Kubernetes MCP server (read-only identity)."""

    async def scale(self, namespace: str, deployment: str, replicas: int, dry_run: bool) -> str:
        """Mutation via a separate identity. Returns a short summary."""


class Notifier(Protocol):
    async def post(self, channel: str, text: str, thread_ts: str | None = None) -> None: ...
