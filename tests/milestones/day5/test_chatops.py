"""Day 5 ChatOps bot contract tests.

Synchronous on purpose: the verifier runs pytest with plugin autoload disabled, so no async
plugin is available. All I/O is replaced by in-process doubles (no Slack, MCP or cluster).
Scenario names required by scripts/verify.py: test_permission_denied, test_approval_required,
test_approval_bound_to_action, test_duplicate_event, test_invalid_signature.
Audit events are also written to INSIGHTHUB_VERIFY_OBSERVATIONS as {run_id, events}.
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(os.environ.get("INSIGHTHUB_REPO_ROOT") or Path(__file__).resolve().parents[3])
sys.path.insert(0, str(ROOT / "chatops-bot"))

from fastapi.testclient import TestClient  # noqa: E402

from app.audit import AuditLog  # noqa: E402
from app.factory import create_app  # noqa: E402
from app.infra import PodInfo  # noqa: E402
from app.intents import parse  # noqa: E402
from app.permissions import ApprovalError, ApprovalStore  # noqa: E402
from app.security import sign  # noqa: E402
from app.settings import Settings  # noqa: E402
from app.store import JobStore  # noqa: E402

SECRET = "test-signing-secret"
APPROVER, OTHER = "UAPPROVER", "UOTHER"
_AUDIT_FILES: list[Path] = []


class FakeInfra:
    def __init__(self, fail_times: int = 0, delay: float = 0.0) -> None:
        self.fail_times, self.delay = fail_times, delay
        self.queries: list[str] = []
        self.scales: list[tuple] = []

    async def prom_query(self, expr):
        if self.fail_times > 0:
            self.fail_times -= 1
            raise RuntimeError("upstream unavailable")
        if self.delay:
            await asyncio.sleep(self.delay)
        self.queries.append(expr)
        if "offset" in expr:
            return [{"metric": {}, "value": 5}]
        if "documents_total" in expr:
            return [{"metric": {"status": "ready"}, "value": 7}, {"metric": {"status": "failed"}, "value": 1}]
        return [{"metric": {}, "value": 1}]

    async def list_pods(self, namespace):
        return [PodInfo("api-1", "Running", True, 0), PodInfo("bad-1", "Pending", False, 3, "ImagePullBackOff")]

    async def scale(self, namespace, deployment, replicas, dry_run):
        self.scales.append((namespace, deployment, replicas, dry_run))
        return f"{deployment} scaled to {replicas} (dry_run={dry_run})"


class FakeNotifier:
    def __init__(self) -> None:
        self.messages: list[tuple[str, str]] = []

    async def post(self, channel, text, thread_ts=None):
        self.messages.append((channel, text))


class Bot:
    def __init__(self, tmp: Path, infra: FakeInfra | None = None, **overrides) -> None:
        self.settings = Settings(signing_secret=SECRET, bot_token="xoxb-test", bot_user_id="UBOT",
                                 approvers=frozenset({APPROVER}), audit_log_path=tmp / "audit.log",
                                 queue_db_path=tmp / "queue.db", backoff_base_seconds=1.0, **overrides)
        _AUDIT_FILES.append(self.settings.audit_log_path)
        self.infra, self.notifier = infra or FakeInfra(), FakeNotifier()
        self.app = create_app(self.settings, self.infra, self.notifier)
        self.client = TestClient(self.app)
        self.audit: AuditLog = self.app.state.audit
        self.store: JobStore = self.app.state.store
        self.worker = self.app.state.worker

    def post(self, body: dict, ts: int | None = None, secret: str = SECRET, signature: str | None = None):
        raw = json.dumps(body).encode()
        stamp = str(int(time.time()) if ts is None else ts)
        return self.client.post("/slack/events", content=raw, headers={
            "x-slack-request-timestamp": stamp, "x-slack-signature": signature or sign(secret, stamp, raw)})

    def mention(self, event_id: str, user: str, text: str):
        return self.post({"type": "event_callback", "event_id": event_id, "event": {
            "type": "app_mention", "user": user, "channel": "C1", "text": f"<@UBOT> {text}", "ts": "1.1"}})

    def drain(self) -> None:
        for i in range(10):
            if not asyncio.run(self.worker.run_once(now=time.time() + i * 100)):
                return

    def ask(self, event_id: str, user: str, text: str) -> str:
        assert self.mention(event_id, user, text).status_code == 200
        self.drain()
        return self.notifier.messages[-1][1]

    def decisions(self, action: str) -> list[str]:
        return [e["decision"] for e in self.audit.read() if e["action"] == action]


@pytest.fixture(autouse=True, scope="module")
def _write_observations():
    yield
    target, run_id = os.environ.get("INSIGHTHUB_VERIFY_OBSERVATIONS"), os.environ.get("INSIGHTHUB_VERIFY_RUN_ID")
    if not target or not run_id:
        return
    events = [json.loads(line) for f in _AUDIT_FILES if f.is_file() for line in f.read_text().splitlines() if line.strip()]
    path = Path(target)
    if path.is_file():  # several test modules may contribute
        events = json.loads(path.read_text())["events"] + events
    path.write_text(json.dumps({"run_id": run_id, "events": events}))


# ---- signature (MH3) -------------------------------------------------------------------------

def test_invalid_signature(tmp_path):
    bot = Bot(tmp_path)
    event = {"type": "event_callback", "event_id": "Ev1", "event": {"type": "app_mention", "user": OTHER, "text": "hi", "channel": "C1"}}
    assert bot.post(event, signature="v0=" + "0" * 64).status_code == 401
    assert bot.post(event, secret="wrong-secret").status_code == 401
    assert bot.client.post("/slack/events", content=b"{}").status_code == 401
    assert bot.store.counts() == {}
    assert "signature_mismatch" in [e.get("reason") for e in bot.audit.read()]
    assert set(bot.decisions("slack.signature")) == {"denied"}


def test_tampered_body_rejected(tmp_path):
    bot = Bot(tmp_path)
    raw = b'{"type":"url_verification","challenge":"a"}'
    ts = str(int(time.time()))
    response = bot.client.post("/slack/events", content=raw.replace(b'"a"', b'"b"'),
                               headers={"x-slack-request-timestamp": ts, "x-slack-signature": sign(SECRET, ts, raw)})
    assert response.status_code == 401
    assert "challenge" not in response.text


def test_replay_window_five_minutes(tmp_path):
    bot = Bot(tmp_path)
    challenge = {"type": "url_verification", "challenge": "c123"}
    now = int(time.time())
    assert bot.post(challenge, ts=now - 299).json() == {"challenge": "c123"}
    assert bot.post(challenge, ts=now - 301).status_code == 401
    assert bot.post(challenge, ts=now + 301).status_code == 401
    assert bot.post(challenge, ts=now).json() == {"challenge": "c123"}
    raw = json.dumps(challenge).encode()
    assert bot.client.post("/slack/events", content=raw, headers={
        "x-slack-request-timestamp": "not-a-number", "x-slack-signature": sign(SECRET, "not-a-number", raw)}).status_code == 401
    assert "stale_timestamp" in [e.get("reason") for e in bot.audit.read()]


def test_unconfigured_secret_fails_closed(tmp_path):
    settings = Settings(signing_secret="", audit_log_path=tmp_path / "a.log", queue_db_path=tmp_path / "q.db")
    client = TestClient(create_app(settings, FakeInfra(), FakeNotifier()))
    raw = b'{"type":"url_verification","challenge":"x"}'
    assert client.post("/slack/events", content=raw, headers={
        "x-slack-request-timestamp": str(int(time.time())), "x-slack-signature": sign("", "1", raw)}).status_code == 401
    assert client.get("/healthz").json()["ready"] is False


def test_healthz(tmp_path):
    body = Bot(tmp_path).client.get("/healthz")
    assert body.status_code == 200 and body.json()["ready"] is True


# ---- permissions (MH9) -----------------------------------------------------------------------

def test_permission_denied(tmp_path):
    bot = Bot(tmp_path)
    assert "user_not_approver" in bot.ask("Ev10", OTHER, "scale api to 3")
    assert "replicas_out_of_range" in bot.ask("Ev11", APPROVER, "scale api to 6")
    assert "replicas_out_of_range" in bot.ask("Ev12", APPROVER, "scale api to 0")
    assert "deployment_not_allowed" in bot.ask("Ev13", APPROVER, "scale postgres to 2")
    assert "phá huỷ" in bot.ask("Ev14", APPROVER, "delete namespace insighthub-local")
    assert bot.decisions("k8s.scale") == ["denied"] * 4
    assert bot.decisions("destructive.request") == ["denied"]
    assert bot.infra.scales == []


def test_approval_required(tmp_path):
    bot = Bot(tmp_path)
    reply = bot.ask("Ev20", APPROVER, "scale api to 5")
    assert "confirm " in reply and "60s" in reply
    assert bot.decisions("k8s.scale") == ["approval_required"]
    assert bot.infra.scales == []  # nothing executes before confirmation
    token = reply.split("confirm ")[1].split("`")[0]
    assert "dry-run" in bot.ask("Ev21", APPROVER, f"confirm {token}")
    assert bot.infra.scales == [("insighthub-local", "insighthub-api", 5, True)]
    assert bot.decisions("k8s.scale.execute") == ["allowed"]
    assert token not in (bot.settings.audit_log_path.read_text())  # tokens never reach the audit log


def test_approval_bound_to_action(tmp_path):
    now = [1000.0]
    store = ApprovalStore(ttl_seconds=60, clock=lambda: now[0])
    args = {"deployment": "insighthub-api", "replicas": 5}
    approval = store.issue(APPROVER, "k8s.scale", args)
    with pytest.raises(ApprovalError, match="other_user"):
        store.redeem(approval.token, OTHER)
    with pytest.raises(ApprovalError, match="other_action"):
        store.redeem(approval.token, APPROVER, "k8s.scale", {"deployment": "insighthub-api", "replicas": 4})
    with pytest.raises(ApprovalError, match="other_action"):
        store.redeem(approval.token, APPROVER, "k8s.delete", args)
    assert store.redeem(approval.token, APPROVER, "k8s.scale", args).args == args
    with pytest.raises(ApprovalError, match="unknown_token"):  # single use
        store.redeem(approval.token, APPROVER)
    late = store.issue(APPROVER, "k8s.scale", args)
    now[0] += 60
    with pytest.raises(ApprovalError, match="expired"):
        store.redeem(late.token, APPROVER)
    # end-to-end: another user's confirm is denied and nothing runs
    bot = Bot(tmp_path)
    token = bot.ask("Ev30", APPROVER, "scale api to 2").split("confirm ")[1].split("`")[0]
    assert "other_user" in bot.ask("Ev31", OTHER, f"confirm {token}")
    assert bot.infra.scales == []
    assert bot.decisions("k8s.scale.confirm") == ["denied"]


# ---- events, queue, dedup (NFR) --------------------------------------------------------------

def test_duplicate_event(tmp_path):
    bot = Bot(tmp_path)
    assert bot.mention("EvDup", OTHER, "InsightHub có healthy không?").status_code == 200
    assert bot.mention("EvDup", OTHER, "InsightHub có healthy không?").status_code == 200
    bot.drain()
    assert len(bot.notifier.messages) == 1
    assert bot.store.counts() == {"done": 1}
    assert "duplicate_ignored" in [e.get("reason") for e in bot.audit.read()]


def test_ack_is_fast_and_not_blocked_by_tools(tmp_path):
    bot = Bot(tmp_path, FakeInfra(delay=5.0))
    started = time.monotonic()
    assert bot.mention("EvSlow", OTHER, "pod nào lỗi").status_code == 200
    assert time.monotonic() - started < 1.0
    assert bot.notifier.messages == [] and bot.store.counts() == {"pending": 1}


def test_ignores_bot_and_other_events(tmp_path):
    bot = Bot(tmp_path)
    assert bot.mention("EvSelf", "UBOT", "healthy?").status_code == 200
    bot.post({"type": "event_callback", "event_id": "EvBot", "event": {"type": "app_mention", "bot_id": "B1", "user": OTHER, "text": "x"}})
    bot.post({"type": "event_callback", "event_id": "EvMsg", "event": {"type": "message", "user": OTHER, "text": "x"}})
    assert bot.store.counts() == {}


def test_retry_bounded_with_backoff(tmp_path):
    bot = Bot(tmp_path, FakeInfra(fail_times=2))
    assert "healthy" in bot.ask("EvRetry", OTHER, "healthy?")  # succeeds on the third attempt
    dead = Bot(tmp_path / "dead", FakeInfra(fail_times=99))
    dead.mention("EvDead", OTHER, "healthy?")
    dead.drain()
    assert dead.store.counts() == {"dead": 1}
    assert "3 lần" in dead.notifier.messages[-1][1]


def test_queue_survives_restart(tmp_path):
    first = JobStore(tmp_path / "q.db")
    assert first.enqueue("EvA", {"user": "U1"}) is True
    assert first.claim() is not None  # crashes while running
    first.close()
    second = JobStore(tmp_path / "q.db")
    assert second.enqueue("EvA", {"user": "U1"}) is False
    job = second.claim()
    assert job is not None and job.event_id == "EvA"


# ---- intents (MH6/MH7/MH8) -------------------------------------------------------------------

@pytest.mark.parametrize("text,kind", [
    ("InsightHub có healthy không?", "health"), ("api healthy?", "health"),
    ("Hôm nay ingest bao nhiêu doc?", "ingest"), ("ingest count today?", "ingest"),
    ("Pod nào đang lỗi?", "pods"), ("which pods failing?", "pods"),
    ("scale api to 5", "scale"), ("confirm ABC12345", "confirm"),
    ("xoá pod api", "destructive"), ("chào", "help"),
])
def test_intent_parsing(text, kind):
    assert parse(text).kind == kind


@pytest.mark.parametrize("text", [
    "`confirm ABC12345`", "*confirm ABC12345*", "_confirm ABC12345_", "~confirm ABC12345~",
    "```confirm ABC12345```", "confirm `ABC12345`", "<@UBOT> `confirm abc12345`", "  `Confirm ABC12345`.  ",
])
def test_slack_formatting_is_stripped(text):
    intent = parse(text)
    assert intent.kind == "confirm" and intent.args == {"token": "ABC12345"}
    assert parse("`scale api to 5`").kind == "scale"
    assert parse("*Pod nào đang lỗi?*").kind == "pods"


def test_confirm_with_backticks_executes(tmp_path):
    bot = Bot(tmp_path)
    token = bot.ask("Ev60", APPROVER, "scale api to 5").split("confirm ")[1].split("`")[0]
    assert "dry-run" in bot.ask("Ev61", APPROVER, f"`confirm {token}`")  # text as copied from the bot's message
    assert bot.infra.scales == [("insighthub-local", "insighthub-api", 5, True)]


def test_three_intents_use_mcp_and_are_audited(tmp_path):
    bot = Bot(tmp_path)
    assert "healthy" in bot.ask("Ev40", OTHER, "InsightHub có healthy không?")
    reply = bot.ask("Ev41", OTHER, "Hôm nay ingest bao nhiêu doc?")
    assert "+2" in reply and "5 → 7" in reply and "*8*" in reply  # ready 7 now vs 5 at 00:00; total 8
    assert any("offset" in q and "ready" in q for q in bot.infra.queries)
    pods = bot.ask("Ev42", OTHER, "Pod nào đang lỗi?")
    assert "bad-1" in pods and "api-1" not in pods
    actions = {e["action"] for e in bot.audit.read()}
    assert {"mcp:prometheus.query", "mcp:kubernetes.pods_list"} <= actions


def test_ingest_without_midnight_baseline(tmp_path):
    class NoBaseline(FakeInfra):
        async def prom_query(self, expr):
            return [] if "offset" in expr else await super().prom_query(expr)
    reply = Bot(tmp_path, NoBaseline()).ask("Ev45", OTHER, "ingest count today?")
    assert "Chưa có dữ liệu lúc 00:00" in reply and "*8*" in reply


def test_seconds_since_local_midnight():
    from datetime import datetime, timedelta, timezone
    from app.service import seconds_since_local_midnight
    tz7 = timezone(timedelta(hours=7))
    assert seconds_since_local_midnight(datetime(2026, 9, 30, 0, 0, 0, tzinfo=tz7)) == 0
    assert seconds_since_local_midnight(datetime(2026, 9, 30, 14, 30, 5, tzinfo=tz7)) == 14 * 3600 + 30 * 60 + 5
    # 17:00 UTC is 00:00 the next day in +07
    assert seconds_since_local_midnight(datetime(2026, 9, 29, 17, 0, 1, tzinfo=timezone.utc)) == 1


def test_audit_schema_and_no_secrets(tmp_path):
    bot = Bot(tmp_path)
    bot.ask("Ev50", OTHER, "healthy?")
    bot.ask("Ev51", OTHER, "scale api to 3")
    text = bot.settings.audit_log_path.read_text()
    for event in bot.audit.read():
        assert all(event.get(k) for k in ("timestamp", "event_id", "action", "decision", "user"))
        assert event["decision"] in {"allowed", "denied", "approval_required"}
    assert SECRET not in text and "xoxb-test" not in text
