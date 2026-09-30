"""Coding workflow guardrails (no network): docstring-only proposals pass, behaviour changes and secrets do not."""
import importlib.util
import os
from pathlib import Path

import pytest

ROOT = Path(os.environ.get("INSIGHTHUB_REPO_ROOT") or Path(__file__).resolve().parents[3])
_spec = importlib.util.spec_from_file_location("coding_workflow", ROOT / "tools" / "coding-workflow" / "run.py")
cw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cw)

ORIGINAL = "def add(a, b):\n    return a + b\n"


def test_docstring_only_change_is_accepted():
    ok, reason = cw.validate_proposal(ORIGINAL, 'def add(a, b):\n    """Add two numbers."""\n    return a + b\n')
    assert ok, reason


@pytest.mark.parametrize("proposal", [
    "def add(a, b):\n    return a - b\n",
    "def add(a, b):\n    import os\n    return a + b\n",
    "def add(a, b:\n    return a + b\n",
    ORIGINAL,
])
def test_behaviour_change_invalid_or_identical_proposals_are_rejected(proposal):
    assert cw.validate_proposal(ORIGINAL, proposal)[0] is False


def test_function_lookup_and_code_extraction():
    source = "x = 1\n\n" + ORIGINAL
    code, start, end = cw.function_source(source, "add")
    assert code == ORIGINAL and (start, end) == (3, 4)
    assert cw.extract_code("Đây:\n```python\n" + ORIGINAL + "```\n") == ORIGINAL


def test_secret_files_and_key_shapes_never_enter_the_prompt(tmp_path):
    (tmp_path / ".env").write_text("OPENAI_API_KEY=sk-abcdefghijkl")
    with pytest.raises(ValueError):
        cw.safe_read(tmp_path / ".env")
    note = tmp_path / "note.py"
    note.write_text("token = 'sk-abcdefghijkl123'\n")
    assert "sk-abcdefghijkl123" not in cw.safe_read(note)
