#!/usr/bin/env python3
"""Build evidence/day5-audit.json from the real chatops-audit.log and evidence/day5.json.

Run LAST, after the source is frozen (day5.json binds source_sha256)."""
import datetime as dt, hashlib, json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG = ROOT / "chatops-bot" / "chatops-audit.log"
events = [json.loads(line) for line in LOG.read_text(encoding="utf-8").splitlines() if line.strip()]
decisions = {e["decision"] for e in events}
assert {"denied", "approval_required"} <= decisions, decisions
audit = ROOT / "evidence" / "day5-audit.json"
audit.write_text(json.dumps({"run_id": "live-slack-2026-09-30", "source": "chatops-bot/chatops-audit.log (live Slack)",
                             "events": events}, ensure_ascii=False, indent=1), encoding="utf-8")
sha = lambda p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
fp = subprocess.run([sys.executable, str(ROOT / "scripts/verify.py"), "fingerprint"], capture_output=True, text=True, check=True).stdout.strip()
day5 = {
    "schema_version": 1, "day": 5, "mode": "real",
    "observed_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_sha256": fp,
    "note": "REAL: Slack bot live via ngrok on local host; MCP Prometheus + Kubernetes (read-only) on kind insighthub-lab; scale executes --dry-run=server; queue is SQLite (not Redis/ARQ); rule-based intents. See infra/DAY5-CHECKLIST.md section D.",
    "artifacts": {
        "permissions": {"path": "chatops-bot/app/permissions.py", "sha256": sha("chatops-bot/app/permissions.py")},
        "audit": {"path": "evidence/day5-audit.json", "sha256": sha("evidence/day5-audit.json")},
    },
}
(ROOT / "evidence" / "day5.json").write_text(json.dumps(day5, indent=2, ensure_ascii=False), encoding="utf-8")
print(len(events), "events;", sorted(decisions), "; source_sha256", fp[:12])
