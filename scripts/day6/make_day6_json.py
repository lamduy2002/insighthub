#!/usr/bin/env python3
"""Build evidence/day6.json (the envelope verify.py reads). Run LAST, after the source is frozen and
eval-final.json / cost-day6.json / eval-initial.json exist."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "security" / "eval"))
import harness  # noqa: E402

ARTIFACTS = {
    "dataset": "security/dataset.json",
    "eval_initial": "evidence/eval-initial.json",
    "eval_final": "evidence/eval-final.json",
    "cost": "evidence/cost-day6.json",
}
envelope = {"schema_version": 1, "day": 6, "mode": "real", "observed_at": harness.now_iso(),
            "source_sha256": harness.source_digest(),
            "artifacts": {role: {"path": path, "sha256": harness.sha256_file(ROOT / path)}
                          for role, path in ARTIFACTS.items()}}
(ROOT / "evidence" / "day6.json").write_text(json.dumps(envelope, indent=2))
print("evidence/day6.json written for source", envelope["source_sha256"][:12])
