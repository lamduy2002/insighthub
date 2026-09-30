#!/usr/bin/env python3
"""Drive the real ChatOps bot app with locally signed Slack events so the `summarize` intent makes a real call
through LiteLLM with the chatops-bot virtual key (no Slack, no ngrok). Tool data comes from --infra:
`live` (Prometheus HTTP + kubectl read-only, needs port-forward) or `static` (labelled in the output).
Writes evidence/day6-bot-trace.json (audit events with gateway request ids)."""
import argparse
import asyncio
import json
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "chatops-bot"))

from fastapi.testclient import TestClient  # noqa: E402

from app.factory import create_app  # noqa: E402
from app.infra import PodInfo  # noqa: E402
from app.security import sign  # noqa: E402
from app.settings import Settings  # noqa: E402


class StaticInfra:
    async def prom_query(self, expr):
        return [{"metric": {}, "value": 1}]

    async def list_pods(self, namespace):
        return [PodInfo("insighthub-api-1", "Running", True, 0), PodInfo("insighthub-web-1", "Running", True, 0)]

    async def scale(self, *a, **k):
        raise AssertionError("summarize must never mutate")


class Notifier:
    def __init__(self):
        self.messages = []

    async def post(self, channel, text, thread_ts=None):
        self.messages.append(text)


def env_value(name):
    for line in (ROOT / ".env").read_text().splitlines():
        if line.startswith(name + "="):
            return line.split("=", 1)[1]
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--infra", choices=["static", "live"], default="static")
    ap.add_argument("--questions", nargs="*", default=["tóm tắt tình hình", "summarize the cluster status"])
    args = ap.parse_args()
    tmp = Path(tempfile.mkdtemp())
    settings = Settings(signing_secret="local-sign", bot_token="xoxb-local", bot_user_id="UBOT",
                        audit_log_path=tmp / "audit.log", queue_db_path=tmp / "q.db",
                        llm_api_key=env_value("LITELLM_KEY_CHATOPS_BOT"))
    notifier = Notifier()
    if args.infra == "live":
        from app.adapters import build_infra
        infra = build_infra(settings)
    else:
        infra = StaticInfra()
    app = create_app(settings, infra, notifier)
    client = TestClient(app)
    for i, question in enumerate(args.questions):
        raw = json.dumps({"type": "event_callback", "event_id": f"EvTraffic{i}", "event": {
            "type": "app_mention", "user": "UEXAMPLE", "channel": "C1", "text": f"<@UBOT> {question}", "ts": "1.1"}}).encode()
        stamp = str(int(time.time()))
        r = client.post("/slack/events", content=raw, headers={
            "x-slack-request-timestamp": stamp, "x-slack-signature": sign("local-sign", stamp, raw)})
        assert r.status_code == 200
        asyncio.run(app.state.worker.run_once())
        print(f"Q: {question}\nA: {notifier.messages[-1]}\n")
    events = app.state.audit.read()
    trace = {"infra": args.infra, "audit_events": [e for e in events if e["action"].startswith(("llm.", "intent.summarize"))],
             "replies": notifier.messages}
    out = ROOT / "evidence" / "day6-bot-trace.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(trace, ensure_ascii=False, indent=1))
    print("trace ->", out)


if __name__ == "__main__":
    main()
