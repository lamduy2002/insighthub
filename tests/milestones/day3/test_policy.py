import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(os.environ["INSIGHTHUB_REPO_ROOT"])
POLICY_DIR = REPO_ROOT / "infra" / "policy" / "terraform"
FIXTURES_DIR = Path(__file__).parent / "fixtures"


def _run_conftest(fixture_name):
    conftest_bin = shutil.which("conftest")
    if conftest_bin is None:
        pytest.fail("Missing tool: conftest (khong tim thay binary conftest trong PATH)")
    fixture_path = FIXTURES_DIR / fixture_name
    assert fixture_path.is_file(), f"Missing fixture: {fixture_path}"
    result = subprocess.run(
        [conftest_bin, "test", "--policy", str(POLICY_DIR), str(fixture_path)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=60,
    )
    return result


def test_policy_allows_valid():
    result = _run_conftest("valid_plan.json")
    assert result.returncode == 0, (
        f"conftest test tren valid_plan.json phai PASS (exit 0), "
        f"nhung exit={result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_policy_denies_unsafe():
    result = _run_conftest("invalid_plan.json")
    assert result.returncode != 0, (
        f"conftest test tren invalid_plan.json phai FAIL (exit != 0), "
        f"nhung exit={result.returncode}\nstdout:\n{result.stdout}"
    )
    output = result.stdout
    expected_substrings = [
        "publicly_accessible",
        "owner",
        "transit_encryption_enabled",
        "instance_class",
    ]
    missing = [s for s in expected_substrings if s not in output]
    assert not missing, (
        f"Thieu deny message mong doi: {missing}\nOutput day du:\n{output}"
    )
