"""Job handler (intent -> permission -> tool -> audit -> reply) and the retrying worker."""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from typing import Any

from .audit import AuditLog
from .infra import Infra, Notifier, PodInfo
from .intents import Intent, parse
from .llm import LLMError, Summarizer
from .permissions import ApprovalError, ApprovalStore, Tier, authorize
from .settings import Settings
from .store import JobStore

HELP = ("Tôi trả lời 3 câu: *InsightHub có healthy không?*, *Hôm nay ingest bao nhiêu doc?*, "
        "*Pod nào đang lỗi?*. Thay đổi: `scale api to N` (N 1-5) rồi `confirm <token>` trong 60s.")

HEALTH_QUERIES = {
    "api": 'min(up{job="insighthub-api"})',
    "postgres": "min(pg_up)",
    "redis": "min(redis_up)",
    "web": 'min(probe_success{job="insighthub-web-probe"})',
}


LOCAL_TZ = timezone(timedelta(hours=7))  # "hôm nay" = từ 00:00 giờ máy (+07)


def seconds_since_local_midnight(now: datetime | None = None) -> int:
    local = (now or datetime.now(LOCAL_TZ)).astimezone(LOCAL_TZ)
    return int((local - local.replace(hour=0, minute=0, second=0, microsecond=0)).total_seconds())


class Handler:
    def __init__(self, settings: Settings, audit: AuditLog, infra: Infra, notifier: Notifier,
                 approvals: ApprovalStore, llm: Summarizer | None = None) -> None:
        self.settings, self.audit, self.infra = settings, audit, infra
        self.notifier, self.approvals, self.llm = notifier, approvals, llm

    async def _reply(self, payload: dict[str, Any], text: str) -> None:
        await self.notifier.post(payload["channel"], text, payload.get("thread_ts") or payload.get("ts"))

    async def _prom(self, user: str, expr: str, event_id: str) -> list[dict[str, Any]]:
        rows = await self.infra.prom_query(expr)
        self.audit.record(action="mcp:prometheus.query", decision="allowed", user=user,
                          args={"expr": expr}, result=f"{len(rows)} series", slack_event_id=event_id)
        return rows

    async def handle(self, event_id: str, payload: dict[str, Any]) -> None:
        user = payload["user"]
        intent = parse(payload.get("text", ""))
        method = getattr(self, f"_on_{intent.kind}")
        await method(event_id, payload, user, intent)

    async def _on_help(self, event_id: str, payload: dict[str, Any], user: str, intent: Intent) -> None:
        self.audit.record(action="intent.help", decision="allowed", user=user, slack_event_id=event_id)
        await self._reply(payload, HELP)

    async def _on_health(self, event_id: str, payload: dict[str, Any], user: str, intent: Intent) -> None:
        verdict = authorize(self.settings, user, Tier.READ)
        self.audit.record(action="intent.health", decision=verdict.decision, user=user, slack_event_id=event_id)
        lines, healthy = [], True
        for name, expr in HEALTH_QUERIES.items():
            rows = await self._prom(user, expr, event_id)
            value = rows[0]["value"] if rows else None
            ok = value == 1
            healthy = healthy and ok
            lines.append(f"{'✅' if ok else '❌'} {name}: {'up' if ok else 'down' if value == 0 else 'không có dữ liệu'}")
        await self._reply(payload, ("InsightHub *healthy*" if healthy else "InsightHub *có vấn đề*") + "\n" + "\n".join(lines))

    async def _on_ingest(self, event_id: str, payload: dict[str, Any], user: str, intent: Intent) -> None:
        verdict = authorize(self.settings, user, Tier.READ)
        self.audit.record(action="intent.ingest", decision=verdict.decision, user=user, slack_event_id=event_id)
        rows = await self._prom(user, "sum by (status) (insighthub_documents_total)", event_id)
        if not rows:
            await self._reply(payload, "Chưa có số liệu tài liệu từ Prometheus.")
            return
        counts = {r["metric"].get("status", "?"): int(r["value"]) for r in rows}
        total = sum(counts.values())
        detail = ", ".join(f"{k}: {v}" for k, v in sorted(counts.items()))
        ready = counts.get("ready", 0)
        offset = seconds_since_local_midnight()
        base = await self._prom(user, f'sum(insighthub_documents_total{{status="ready"}} offset {offset}s)', event_id)
        if base:
            before = int(base[0]["value"])
            head = f"Hôm nay (từ 00:00 +07) ready tăng *{ready - before:+d}* doc ({before} → {ready})."
        else:
            head = "Chưa có dữ liệu lúc 00:00 để tính số tăng trong ngày."
        await self._reply(payload, f"{head} Tổng hiện có: *{total}* ({detail}). "
                                   "Số tăng là chênh lệch ròng của gauge `insighthub_documents_total`.")

    async def _on_pods(self, event_id: str, payload: dict[str, Any], user: str, intent: Intent) -> None:
        verdict = authorize(self.settings, user, Tier.READ)
        self.audit.record(action="intent.pods", decision=verdict.decision, user=user, slack_event_id=event_id)
        pods = await self.infra.list_pods(self.settings.namespace)
        self.audit.record(action="mcp:kubernetes.pods_list", decision="allowed", user=user,
                          args={"namespace": self.settings.namespace}, result=f"{len(pods)} pods",
                          slack_event_id=event_id)
        bad = [p for p in pods if _pod_failing(p)]
        if not bad:
            await self._reply(payload, f"Không có pod lỗi trong `{self.settings.namespace}` ({len(pods)} pod).")
            return
        rows = [f"• `{p.name}`: {p.phase}{' / ' + p.reason if p.reason and p.reason != p.phase else ''}, restarts={p.restarts}" for p in bad]
        await self._reply(payload, f"*{len(bad)}/{len(pods)}* pod đang lỗi:\n" + "\n".join(rows))

    async def _on_summarize(self, event_id: str, payload: dict[str, Any], user: str, intent: Intent) -> None:
        verdict = authorize(self.settings, user, Tier.READ)
        self.audit.record(action="intent.summarize", decision=verdict.decision, user=user, slack_event_id=event_id)
        lines = []
        for name, expr in HEALTH_QUERIES.items():
            rows = await self._prom(user, expr, event_id)
            value = rows[0]["value"] if rows else None
            lines.append(f"{name}: {'up' if value == 1 else 'down' if value == 0 else 'không có dữ liệu'}")
        pods = await self.infra.list_pods(self.settings.namespace)
        self.audit.record(action="mcp:kubernetes.pods_list", decision="allowed", user=user,
                          args={"namespace": self.settings.namespace}, result=f"{len(pods)} pods",
                          slack_event_id=event_id)
        bad = [f"{p.name}: {p.phase}{' / ' + p.reason if p.reason else ''}, restarts={p.restarts}"
               for p in pods if _pod_failing(p)]
        facts = "\n".join(lines + [f"pods lỗi: {len(bad)}/{len(pods)}"] + bad)
        if self.llm is None:
            await self._reply(payload, "Tóm tắt bằng AI chưa được cấu hình. Số liệu:\n" + facts)
            return
        try:
            summary = await self.llm.summarize(facts)
        except LLMError as exc:
            # Keep only the error class; fall back to the plain facts (never to a different provider).
            self.audit.record(action="llm.summarize", decision="allowed", user=user,
                              result=f"fallback_no_llm: {exc}", slack_event_id=event_id)
            await self._reply(payload, "Không gọi được mô hình AI, đây là số liệu thô:\n" + facts)
            return
        self.audit.record(action="llm.summarize", decision="allowed", user=user,
                          result=f"request_id={summary.request_id} in={summary.input_tokens} out={summary.output_tokens}",
                          slack_event_id=event_id)
        await self._reply(payload, f"{summary.text}\n_(AI tóm tắt từ số liệu Prometheus/Kubernetes; "
                                   f"chỉ đọc, không thay đổi hạ tầng.)_")

    async def _on_destructive(self, event_id: str, payload: dict[str, Any], user: str, intent: Intent) -> None:
        verdict = authorize(self.settings, user, Tier.DESTRUCTIVE)
        self.audit.record(action="destructive.request", decision=verdict.decision, user=user,
                          reason=verdict.reason, slack_event_id=event_id)
        await self._reply(payload, "Từ chối: hành động phá huỷ không được bot hỗ trợ.")

    async def _on_scale(self, event_id: str, payload: dict[str, Any], user: str, intent: Intent) -> None:
        verdict = authorize(self.settings, user, Tier.WRITE, intent.args)
        if verdict.decision != "approval_required":
            self.audit.record(action="k8s.scale", decision=verdict.decision, user=user,
                              args=intent.args, reason=verdict.reason, slack_event_id=event_id)
            await self._reply(payload, f"Từ chối scale: {verdict.reason}.")
            return
        approval = self.approvals.issue(user, "k8s.scale", intent.args)
        self.audit.record(action="k8s.scale", decision="approval_required", user=user, args=intent.args,
                          reason=f"token_expires_in_{self.approvals.ttl}s", slack_event_id=event_id)
        await self._reply(payload, f"Cần xác nhận: scale `{intent.args['deployment']}` → {intent.args['replicas']}. "
                                   f"Gõ `confirm {approval.token}` trong {self.approvals.ttl}s.")

    async def _on_confirm(self, event_id: str, payload: dict[str, Any], user: str, intent: Intent) -> None:
        try:
            approval = self.approvals.redeem(intent.args["token"], user)
        except ApprovalError as exc:
            self.audit.record(action="k8s.scale.confirm", decision="denied", user=user, reason=exc.reason,
                              slack_event_id=event_id)
            await self._reply(payload, f"Từ chối xác nhận: {exc.reason}.")
            return
        args = approval.args
        summary = await self.infra.scale(self.settings.namespace, args["deployment"], args["replicas"], dry_run=True)
        self.audit.record(action="k8s.scale.execute", decision="allowed", user=user, args=args,
                          result=summary, slack_event_id=event_id)
        await self._reply(payload, f"Đã thực thi (dry-run server): {summary}")


def _pod_failing(pod: PodInfo) -> bool:
    return pod.phase not in {"Running", "Succeeded"} or (pod.phase == "Running" and not pod.ready) \
        or pod.reason in {"CrashLoopBackOff", "ImagePullBackOff", "ErrImagePull", "OOMKilled"}


class Worker:
    def __init__(self, store: JobStore, handler: Handler, settings: Settings, audit: AuditLog,
                 notifier: Notifier) -> None:
        self.store, self.handler, self.settings, self.audit, self.notifier = store, handler, settings, audit, notifier

    async def run_once(self, now: float | None = None) -> bool:
        job = self.store.claim(now)
        if job is None:
            return False
        try:
            await self.handler.handle(job.event_id, job.payload)
        except Exception as exc:  # noqa: BLE001 - retry any tool failure; keep only the class name
            outcome = self.store.fail(job.event_id, type(exc).__name__, self.settings.max_attempts,
                                      self.settings.backoff_base_seconds, now)
            self.audit.record(action="worker.job", decision="allowed", user=job.payload.get("user", "unknown"),
                              result=f"{outcome}: {type(exc).__name__}", slack_event_id=job.event_id)
            if outcome == "dead":
                try:
                    await self.notifier.post(job.payload["channel"], "Xin lỗi, tôi không lấy được dữ liệu sau 3 lần thử.",
                                             job.payload.get("thread_ts") or job.payload.get("ts"))
                except Exception:  # noqa: BLE001
                    pass
        else:
            self.store.complete(job.event_id)
        return True

    async def run_forever(self, idle_seconds: float = 0.25) -> None:
        while True:
            if not await self.run_once():
                await asyncio.sleep(idle_seconds)
