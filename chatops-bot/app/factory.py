"""App factory: verify signature -> dedup + durable enqueue -> ACK; worker replies later."""
from __future__ import annotations

import asyncio
import json
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .audit import AuditLog
from .infra import Infra, Notifier
from .permissions import ApprovalStore
from .security import SignatureError, verify_signature
from .service import Handler, Worker
from .settings import Settings
from .store import JobStore


def create_app(settings: Settings | None = None, infra: Infra | None = None,
               notifier: Notifier | None = None, store: JobStore | None = None,
               audit: AuditLog | None = None, approvals: ApprovalStore | None = None,
               run_worker: bool = False) -> FastAPI:
    settings = settings or Settings.from_env()
    audit = audit or AuditLog(settings.audit_log_path)
    store = store or JobStore(settings.queue_db_path)
    approvals = approvals or ApprovalStore(settings.approval_ttl_seconds)

    if run_worker and (infra is None or notifier is None):
        from .adapters import build_infra, build_notifier
        infra = infra or build_infra(settings)
        notifier = notifier or build_notifier(settings)
    handler = Handler(settings, audit, infra, notifier, approvals) if infra and notifier else None
    worker = Worker(store, handler, settings, audit, notifier) if handler and notifier else None

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        task = asyncio.create_task(worker.run_forever()) if (run_worker and worker) else None
        try:
            yield
        finally:
            if task:
                task.cancel()

    app = FastAPI(title="InsightHub ChatOps bot", version="1.0.0", lifespan=lifespan)
    app.state.settings, app.state.audit, app.state.store = settings, audit, store
    app.state.approvals, app.state.worker = approvals, worker

    @app.get("/healthz")
    def health() -> dict[str, Any]:
        return {"status": "ok" if settings.ready else "degraded", "ready": settings.ready,
                "transport": "http", "queue": store.counts()}

    @app.post("/slack/events")
    async def slack_events(request: Request) -> JSONResponse:
        body = await request.body()  # raw bytes: the signature covers them exactly
        try:
            verify_signature(settings.signing_secret, request.headers.get("x-slack-request-timestamp"),
                             request.headers.get("x-slack-signature"), body,
                             window_seconds=settings.replay_window_seconds)
        except SignatureError as exc:
            audit.record(action="slack.signature", decision="denied", user="unknown", reason=exc.reason)
            return JSONResponse({"error": "invalid_signature"}, status_code=401)
        try:
            data = json.loads(body)
            if not isinstance(data, dict):
                raise ValueError
        except ValueError:
            return JSONResponse({"error": "invalid_json"}, status_code=400)
        if data.get("type") == "url_verification":
            return JSONResponse({"challenge": str(data.get("challenge", ""))})
        event = data.get("event")
        event_id = data.get("event_id")
        if data.get("type") != "event_callback" or not isinstance(event, dict) or not isinstance(event_id, str):
            return JSONResponse({"ok": True})
        user = str(event.get("user", ""))
        if (event.get("type") != "app_mention" or event.get("bot_id") or event.get("subtype")
                or not user or (settings.bot_user_id and user == settings.bot_user_id)):
            return JSONResponse({"ok": True})  # ignore other events and the bot's own messages
        payload = {"user": user, "channel": str(event.get("channel", "")), "text": str(event.get("text", "")),
                   "ts": str(event.get("ts", "")), "thread_ts": event.get("thread_ts")}
        if store.enqueue(event_id, payload):
            audit.record(action="slack.event", decision="allowed", user=user, slack_event_id=event_id)
        else:
            audit.record(action="slack.event", decision="allowed", user=user, reason="duplicate_ignored",
                         slack_event_id=event_id)
        return JSONResponse({"ok": True})  # ACK now; the worker answers later

    return app
