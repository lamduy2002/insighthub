#!/usr/bin/env python3
"""Coding workflow client (spec 0.5, API-workflow branch): repo context -> proposed change -> saved diff ->
tests in a throwaway worktree -> gateway attribution.

Every model call goes through LiteLLM with the dedicated `coding-workflow` virtual key. The proposal is
accepted only if it is a docstring-only change of one named function (AST identical apart from the
docstring), so a weak model cannot smuggle behaviour changes; the diff is never applied to the working tree
without --apply. Secrets (.env*, key-shaped strings) never enter the prompt.

  python tools/coding-workflow/run.py --file chatops-bot/app/intents.py --function normalize \
      --test-cmd "python -m pytest -c /dev/null -p no:cacheprovider chatops-bot/tests -q"
"""
from __future__ import annotations

import argparse
import ast
import difflib
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SECRET_SHAPES = re.compile(r"sk-[A-Za-z0-9_-]{8,}|xox[bp]-[A-Za-z0-9-]+|AKIA[0-9A-Z]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY")
MAX_CONTEXT_CHARS = 6000


def env_value(name: str, default: str = "") -> str:
    if name in os.environ:
        return os.environ[name]
    env = REPO / ".env"
    if env.is_file():
        for line in env.read_text().splitlines():
            if line.startswith(name + "="):
                return line.split("=", 1)[1].strip()
    return default


def safe_read(path: Path) -> str:
    if path.name.startswith(".env") or path.suffix in {".pem", ".key"}:
        raise ValueError(f"refusing to read secret file: {path.name}")
    return SECRET_SHAPES.sub("[REDACTED]", path.read_text(encoding="utf-8"))


def function_source(source: str, name: str) -> tuple[str, int, int]:
    tree = ast.parse(source)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name:
            lines = source.splitlines(keepends=True)
            return "".join(lines[node.lineno - 1:node.end_lineno]), node.lineno, node.end_lineno
    raise KeyError(f"function {name} not found")


def strip_docstring(code: str) -> str:
    tree = ast.parse(code)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            body = node.body
            if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) \
                    and isinstance(body[0].value.value, str):
                node.body = body[1:] or [ast.Pass()]
    return ast.dump(tree)


def extract_code(reply: str) -> str:
    match = re.search(r"```(?:python)?\n(.*?)```", reply, re.DOTALL)
    return (match.group(1) if match else reply).strip("\n") + "\n"


def validate_proposal(original: str, proposed: str) -> tuple[bool, str]:
    try:
        ast.parse(proposed)
    except SyntaxError as exc:
        return False, f"proposal is not valid Python ({exc.msg})"
    if strip_docstring(original) != strip_docstring(proposed):
        return False, "proposal changes behaviour (AST differs beyond the docstring)"
    if original.strip() == proposed.strip():
        return False, "proposal is identical to the original"
    return True, "docstring-only change"


def call_gateway(prompt: str, base_url: str, key: str, model: str) -> dict:
    body = json.dumps({"model": model, "max_tokens": 600, "temperature": 0, "messages": [
        {"role": "system", "content": "Bạn là trợ lý lập trình. Chỉ trả về mã Python trong một khối ```python."},
        {"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request(base_url.rstrip("/") + "/chat/completions", body, {
        "Content-Type": "application/json", "Authorization": f"Bearer {key}",
        "x-litellm-tags": "app:coding-workflow,purpose:docstring-proposal"})
    with urllib.request.urlopen(req, timeout=240) as resp:
        data = json.load(resp)
        return {"reply": data["choices"][0]["message"]["content"], "usage": data.get("usage") or {},
                "request_id": resp.headers.get("x-litellm-call-id")}


def shadow_spend(request_id: str, master: str, litellm_url: str) -> float | None:
    for _ in range(12):  # spend logs are written every proxy_batch_write_at seconds
        try:
            req = urllib.request.Request(f"{litellm_url}/spend/logs?request_id={request_id}",
                                         headers={"Authorization": f"Bearer {master}"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                rows = json.load(resp)
            if rows:
                return float(rows[0].get("spend") or 0)
        except (urllib.error.URLError, ValueError):
            pass
        time.sleep(3)
    return None


def run_tests(repo: Path, file_rel: str, new_source: str, test_cmd: str) -> dict:
    """Apply the proposal in a detached worktree of HEAD and run the tests there."""
    worktree = Path(tempfile.mkdtemp(prefix="coding-workflow-"))
    subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(worktree), "HEAD"],
                   check=True, capture_output=True)
    try:
        (worktree / file_rel).write_text(new_source, encoding="utf-8")
        proc = subprocess.run(shlex.split(test_cmd), cwd=worktree, capture_output=True, text=True, timeout=900,
                              env={**os.environ, "INSIGHTHUB_REPO_ROOT": str(worktree)})
        return {"exit_code": proc.returncode, "output_tail": (proc.stdout + proc.stderr)[-600:]}
    finally:
        subprocess.run(["git", "-C", str(repo), "worktree", "remove", "--force", str(worktree)], capture_output=True)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", required=True)
    ap.add_argument("--function", required=True)
    ap.add_argument("--test-cmd", default=f"{sys.executable} -m pytest -c /dev/null -p no:cacheprovider chatops-bot/tests -q")
    ap.add_argument("--out", default=str(REPO / "evidence" / "coding-workflow"))
    ap.add_argument("--apply", action="store_true", help="apply the accepted diff to the working tree")
    args = ap.parse_args(argv)

    run_id = uuid.uuid4().hex[:12]
    out = Path(args.out) / run_id
    out.mkdir(parents=True)
    source = safe_read(REPO / args.file)
    original, start, end = function_source(source, args.function)
    status = subprocess.run(["git", "-C", str(REPO), "status", "--short"], capture_output=True, text=True).stdout
    prompt = (f"Repo InsightHub. File {args.file}, dòng {start}-{end}. Thêm một docstring một dòng bằng tiếng Anh vào hàm "
              f"`{args.function}`, không đổi gì khác. Trả về toàn bộ hàm đã cập nhật.\n\n```python\n{original[:MAX_CONTEXT_CHARS]}```\n"
              f"(Số file đang thay đổi trong repo: {len(status.splitlines())}.)")
    result = call_gateway(prompt, env_value("LITELLM_BASE_URL", "http://127.0.0.1:4000/v1"),
                          env_value("LITELLM_KEY_CODING_WORKFLOW"), "chat-small")
    proposed = extract_code(result["reply"])
    ok, reason = validate_proposal(original, proposed)
    lines = source.splitlines(keepends=True)
    new_source = "".join(lines[:start - 1]) + proposed + "".join(lines[end:]) if ok else source
    diff = "".join(difflib.unified_diff(source.splitlines(keepends=True), new_source.splitlines(keepends=True),
                                        f"a/{args.file}", f"b/{args.file}"))
    (out / "proposal.diff").write_text(diff)
    tests = run_tests(REPO, args.file, new_source, args.test_cmd) if ok else {"exit_code": None, "output_tail": "skipped"}
    entry = {"run_id": run_id, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "key_alias": "coding-workflow",
             "request_id": result["request_id"], "model": "chat-small", "file": args.file, "function": args.function,
             "accepted": ok, "reason": reason, "diff_sha256": hashlib.sha256(diff.encode()).hexdigest(),
             "tests_exit_code": tests["exit_code"], "input_tokens": result["usage"].get("prompt_tokens"),
             "output_tokens": result["usage"].get("completion_tokens"),
             "shadow_cost_usd": shadow_spend(result["request_id"], env_value("LITELLM_MASTER_KEY"),
                                             env_value("LITELLM_URL", "http://127.0.0.1:4000")) if result["request_id"] else None,
             "applied": False}
    if ok and tests["exit_code"] == 0 and args.apply:
        (REPO / args.file).write_text(new_source, encoding="utf-8")
        entry["applied"] = True
    (out / "attribution.json").write_text(json.dumps({**entry, "tests_output_tail": tests["output_tail"]}, indent=1))
    with (Path(args.out) / "ledger.jsonl").open("a") as ledger:
        ledger.write(json.dumps(entry) + "\n")
    print(json.dumps(entry, indent=1))
    return 0 if ok and tests["exit_code"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
