#!/usr/bin/env python3
"""Run the frozen dataset live and store the normalized reports.

  run_eval.py initial   -> evidence/eval-initial.raw.json  (source digest = digest at scan time)
  run_eval.py final     -> evidence/eval-final.json + evidence/cost-day6.json
Environment: INSIGHTHUB_API_URL (default http://localhost:18000), key material from .env."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "security" / "eval"))
import harness  # noqa: E402

label = sys.argv[1]
outcome = harness.run_dataset()
evidence = ROOT / "evidence"
evidence.mkdir(exist_ok=True)
if label == "initial":
    (evidence / "eval-initial.raw.json").write_text(json.dumps(outcome["eval"], indent=1))
    (evidence / "cost-initial.raw.json").write_text(json.dumps(outcome["cost"], indent=1))
else:
    (evidence / "eval-final.json").write_text(json.dumps(outcome["eval"], indent=1))
    (evidence / "cost-day6.json").write_text(json.dumps(outcome["cost"], indent=1))
results = outcome["eval"]["results"]
print(f"{label}: {sum(r['passed'] for r in results)}/{len(results)} passed")
for r in results:
    print(f"  {'PASS' if r['passed'] else 'FAIL'} {r['case_id']:<14} {r['severity']:<7} http={r['http_status']} {r['reason']}")
