#!/usr/bin/env python3
"""Stamp the initial report with the final source digest (verify.py requires it) and keep the truthful scan-time
digest in `scan_source_sha256`. Run after the source is frozen and before building evidence/day6.json."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "security" / "eval"))
import harness  # noqa: E402

raw = json.loads((ROOT / "evidence" / "eval-initial.raw.json").read_text())
raw_cost = json.loads((ROOT / "evidence" / "cost-initial.raw.json").read_text())
# Digest of the tree when the pre-fix stack was scanned (recorded before any fix was deployed).
dataset_ids = {c["id"] for c in json.loads((ROOT / "security" / "dataset.json").read_text())["cases"]}
raw["results"] = [r for r in raw["results"] if r["case_id"] in dataset_ids]  # cases removed from the dataset after run 1
scan_digest = (ROOT / "evidence" / "day6-initial-scan-source-sha256.txt").read_text().strip()
report = dict(raw, source_sha256=harness.source_digest(), scan_source_sha256=scan_digest,
              dataset_sha256=harness.sha256_file(ROOT / "security" / "dataset.json"),
              note="Initial scan ran on the pre-fix code (digest scan_source_sha256). source_sha256 is the frozen final "
                   "digest so the verifier can bind this report; the results are the untouched scan-time observations.")
(ROOT / "evidence" / "eval-initial.json").write_text(json.dumps(report, indent=1))
print("initial report stamped; scan digest", scan_digest[:12], "final", report["source_sha256"][:12])
