#!/usr/bin/env python3
"""Regenerates evidence/day4.json (7 artifact roles) for scripts/verify.py day4.

Run it AFTER every source file under observability/, scripts/, infra/ ... is final: the file
records scripts/verify.py's fingerprint of the working tree (dirty edits included), and each
artifact's sha256. Editing any of them afterwards (for example rewriting
observability/mlops-overview-notes.md in your own words) makes verify report INCOMPLETE until
you run this again. evidence/ is excluded from the fingerprint, so this file is safe here.

  python3 evidence/make-day4-json.py
"""
import datetime as dt
import importlib.util
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("verify", ROOT / "scripts" / "verify.py")
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)

ROLES = {
    "dashboard": "observability/grafana-dashboards/insighthub-red.json",
    "rules": "observability/prometheus-rules/anomaly-rules.yaml",
    "rule_tests": "observability/prometheus-rules/anomaly-rules_test.yaml",
    "rca": "evidence/incident-1.json",
    "rca_2": "evidence/incident-2.json",
    "rca_3": "evidence/incident-3.json",
    "mlops_notes": "observability/mlops-overview-notes.md",
}
artifacts = {role: {"path": path, "sha256": verify.sha(ROOT / path)} for role, path in ROLES.items()}
data = {
    "schema_version": verify.VERSION,
    "day": 4,
    "mode": "real",
    "observed_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_sha256": verify.fingerprint(ROOT),
    "note": ("REAL: kind cluster insighthub-lab (local, not EKS), kube-prometheus-stack 91.8.1. "
             "Three incidents injected with scripts/chaos/*, each alert FIRING then RESOLVED and delivered "
             "to Slack #alerts; RCA by independent subagents (Prometheus MCP + Kubernetes MCP) with samples "
             "harvested verbatim by scripts/chaos/harvest-samples.py. Token/cost panels are fixture-mode "
             "estimates. Worker is observed indirectly (cAdvisor + kube-state-metrics + redis queue depth). "
             "See infra/DAY4-CHECKLIST.md."),
    "artifacts": artifacts,
}
(ROOT / "evidence" / "day4.json").write_text(json.dumps(data, indent=2) + "\n")
print("wrote evidence/day4.json  observed_at=" + data["observed_at"] + "  source_sha256=" + data["source_sha256"][:16] + "…")
