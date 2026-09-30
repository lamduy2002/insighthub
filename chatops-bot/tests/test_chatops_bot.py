"""Thin runner: re-runs the milestone scenarios (tests/milestones/day5) from chatops-bot/tests.

The verifier requires the real tests under tests/milestones/day5/; source symlinks are rejected,
so this file loads that module by path and exposes the same tests to `pytest chatops-bot/tests/`.
"""
import importlib.util
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
os.environ.setdefault("INSIGHTHUB_REPO_ROOT", str(ROOT))
_path = ROOT / "tests" / "milestones" / "day5" / "test_chatops.py"
_spec = importlib.util.spec_from_file_location("day5_milestone_tests", _path)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

globals().update({k: v for k, v in vars(_module).items()
                  if k.startswith("test_") or k == "_write_observations"})
