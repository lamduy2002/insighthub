"""Real backends: MCP stdio clients (Prometheus + Kubernetes, read-only), scale executor, Slack notifier.

The read tools are the same MCP servers configured in .mcp.json (Day 2). The scale executor uses a
separate identity (`chatops-mutator`); it is never routed through the read-only MCP server.
"""
from __future__ import annotations

import asyncio
import json
import os
import re
from typing import Any

import httpx
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from .infra import PodInfo
from .settings import Settings

CALL_TIMEOUT_SECONDS = 15.0


class BackendError(Exception):
    """Carries a short reason only; upstream error text is never propagated to logs or Slack."""


class McpServer:
    """One long-lived MCP stdio session, owned by a single task (enter/exit must share a task)."""

    def __init__(self, name: str, params: StdioServerParameters) -> None:
        self.name, self._params = name, params
        self._task: asyncio.Task | None = None
        self._session: ClientSession | None = None
        self._ready = asyncio.Event()
        self._stop = asyncio.Event()
        self._lock = asyncio.Lock()

    async def _run(self) -> None:
        try:
            with open(os.devnull, "w") as quiet:
                async with stdio_client(self._params, errlog=quiet) as (read, write):
                    async with ClientSession(read, write) as session:
                        await session.initialize()
                        self._session = session
                        self._ready.set()
                        await self._stop.wait()
        finally:
            self._session = None
            self._ready.set()

    async def _ensure(self) -> ClientSession:
        async with self._lock:
            if self._task is None or self._task.done() or self._session is None:
                self._ready, self._stop = asyncio.Event(), asyncio.Event()
                self._task = asyncio.create_task(self._run())
                await asyncio.wait_for(self._ready.wait(), CALL_TIMEOUT_SECONDS * 4)
            if self._session is None:
                raise BackendError(f"{self.name}_unavailable")
            return self._session

    async def call(self, tool: str, arguments: dict[str, Any]) -> str:
        try:
            session = await self._ensure()
            result = await asyncio.wait_for(session.call_tool(tool, arguments), CALL_TIMEOUT_SECONDS)
        except Exception as exc:  # noqa: BLE001 - drop the session so the next call reconnects
            self._stop.set()
            raise BackendError(f"{self.name}_{type(exc).__name__}") from None
        if result.is_error:
            raise BackendError(f"{self.name}_tool_error")
        return "".join(getattr(c, "text", "") for c in result.content)

    async def close(self) -> None:
        self._stop.set()
        if self._task:
            await asyncio.gather(self._task, return_exceptions=True)


def parse_prometheus(text: str) -> list[dict[str, Any]]:
    try:
        rows = json.loads(text)["result"]
        return [{"metric": r.get("metric", {}), "value": float(r["value"][1])} for r in rows]
    except (ValueError, KeyError, TypeError, IndexError) as exc:
        raise BackendError("prometheus_bad_response") from exc


_STATUS_TO_PHASE = {"Completed": "Succeeded"}


def parse_pods_table(text: str) -> list[PodInfo]:
    """Parse the Kubernetes MCP table (NAMESPACE APIVERSION KIND NAME READY STATUS RESTARTS ...)."""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return []
    header = re.split(r"\s{2,}", lines[0].strip())
    try:
        i_name, i_ready, i_status, i_restarts = (header.index(c) for c in ("NAME", "READY", "STATUS", "RESTARTS"))
    except ValueError as exc:
        raise BackendError("kubernetes_bad_response") from exc
    pods = []
    for line in lines[1:]:
        cols = re.split(r"\s{2,}", line.strip())
        if len(cols) <= max(i_name, i_ready, i_status, i_restarts):
            continue
        ready = cols[i_ready].split("/")
        status = cols[i_status]
        restarts = re.match(r"\d+", cols[i_restarts])
        pods.append(PodInfo(
            name=cols[i_name], phase=_STATUS_TO_PHASE.get(status, status),
            ready=len(ready) == 2 and ready[0] == ready[1] and ready[0] != "0",
            restarts=int(restarts.group()) if restarts else 0,
            reason="" if status in {"Running", "Completed", "Pending"} else status))
    return pods


class McpInfra:
    def __init__(self, settings: Settings) -> None:
        env = {**os.environ, "PROMETHEUS_URL": settings.prometheus_url}
        self.prometheus = McpServer("prometheus", StdioServerParameters(
            command="npx", args=["-y", "prometheus-mcp@1.1.3", "stdio"], env=env))
        self.kubernetes = McpServer("kubernetes", StdioServerParameters(
            command="npx", args=["-y", "kubernetes-mcp-server@0.0.67", "--read-only",
                                 "--kubeconfig", settings.readonly_kubeconfig], env=os.environ.copy()))
        self._settings = settings

    async def prom_query(self, expr: str) -> list[dict[str, Any]]:
        return parse_prometheus(await self.prometheus.call("prometheus_query", {"query": expr}))

    async def list_pods(self, namespace: str) -> list[PodInfo]:
        return parse_pods_table(await self.kubernetes.call("pods_list_in_namespace", {"namespace": namespace}))

    async def scale(self, namespace: str, deployment: str, replicas: int, dry_run: bool) -> str:
        argv = ["kubectl", "--kubeconfig", self._settings.mutator_kubeconfig, "-n", namespace, "scale",
                f"deployment/{deployment}", f"--replicas={replicas}"]
        if dry_run:
            argv.append("--dry-run=server")
        proc = await asyncio.create_subprocess_exec(*argv, stdout=asyncio.subprocess.PIPE,
                                                    stderr=asyncio.subprocess.DEVNULL)
        try:
            out, _ = await asyncio.wait_for(proc.communicate(), CALL_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            proc.kill()
            raise BackendError("scale_timeout") from None
        if proc.returncode != 0:
            raise BackendError("scale_failed")
        return out.decode(errors="replace").strip()[:200]


class SlackNotifier:
    def __init__(self, token: str) -> None:
        self._token = token

    async def post(self, channel: str, text: str, thread_ts: str | None = None) -> None:
        body: dict[str, Any] = {"channel": channel, "text": text}
        if thread_ts:
            body["thread_ts"] = thread_ts
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post("https://slack.com/api/chat.postMessage", json=body,
                                         headers={"Authorization": f"Bearer {self._token}"})
        data = response.json()
        if response.status_code != 200 or not data.get("ok"):
            raise BackendError("slack_" + str(data.get("error", "http_error"))[:40])


def build_infra(settings: Settings) -> McpInfra:
    return McpInfra(settings)


def build_notifier(settings: Settings) -> SlackNotifier:
    return SlackNotifier(settings.bot_token)
