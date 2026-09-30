"""Deterministic live evaluation of the Day 6 dataset against the real InsightHub /chat endpoint.

Stdlib only (runs inside the verifier's pytest without extra dependencies). Every case is one real
request through InsightHub -> LiteLLM -> Ollama. Output is the normalized evidence format consumed by
scripts/verify.py (`eval_report` / `cost_report`).

Cost: Ollama has no provider fee, so cost_usd is 0 and every entry carries measured `resource_usage`
(wall time and peak memory of the inference stack). LiteLLM shadow prices are reported separately in
extra fields so the budget/attribution story stays visible without pretending it is a bill.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(os.environ.get("INSIGHTHUB_REPO_ROOT") or Path(__file__).resolve().parents[2])
PROVIDER, MODEL = "ollama", "qwen2.5:0.5b"  # upstream behind the gateway aliases (see security/MODELS.md)
STACK_CONTAINERS = ("ollama", "litellm")  # docker compose services of project insighthub-day6
RESPONSE_SEVERITY = {"low", "medium", "high", "critical"}


def env_value(name: str, default: str = "") -> str:
    if name in os.environ:
        return os.environ[name]
    path = REPO / ".env"
    if path.is_file():
        for line in path.read_text().splitlines():
            if line.startswith(name + "="):
                return line.split("=", 1)[1].strip()
    return default


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_digest() -> str:
    spec = importlib.util.spec_from_file_location("insighthub_verify", REPO / "scripts" / "verify.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.fingerprint(REPO)


def load_dataset(path: Path | None = None) -> dict:
    return json.loads((path or REPO / "security" / "dataset.json").read_text(encoding="utf-8"))


# --------------------------------------------------------------------------- measurement
def _containers() -> list[str]:
    names = []
    for service in STACK_CONTAINERS:
        out = subprocess.run(["docker", "ps", "--filter", f"label=com.docker.compose.project=insighthub-day6",
                              "--filter", f"label=com.docker.compose.service={service}", "--format", "{{.Names}}"],
                             capture_output=True, text=True, timeout=15).stdout.split()
        names += out[:1]
    if len(names) != len(STACK_CONTAINERS):
        raise RuntimeError("insighthub-day6 ollama/litellm containers are not running")
    return names


def stack_memory_bytes(names: list[str]) -> int:
    """Sum of cgroup-v2 memory.current of the inference-stack containers."""
    total = 0
    for name in names:
        out = subprocess.run(["docker", "exec", name, "cat", "/sys/fs/cgroup/memory.current"],
                             capture_output=True, text=True, timeout=15).stdout.strip()
        total += int(out)
    return total


class MemorySampler:
    """Samples stack memory (~4 Hz) while a request is in flight and keeps the peak."""

    def __init__(self, names: list[str]):
        self.names, self.peak, self._stop = names, 0, threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                self.peak = max(self.peak, stack_memory_bytes(self.names))
            except (OSError, ValueError, subprocess.SubprocessError):
                pass
            self._stop.wait(0.25)

    def __enter__(self):
        self.peak = stack_memory_bytes(self.names)
        self._thread.start()
        return self

    def __exit__(self, *exc):
        self._stop.set()
        self._thread.join(timeout=5)
        self.peak = max(self.peak, stack_memory_bytes(self.names))


# --------------------------------------------------------------------------- HTTP
def http_json(url: str, body: dict | None = None, headers: dict | None = None, timeout: float = 180.0,
              method: str | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method or ("POST" if body is not None else "GET"),
                                 headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw, status, hdrs = resp.read(), resp.status, resp.headers
    except urllib.error.HTTPError as exc:
        raw, status, hdrs = exc.read(), exc.code, exc.headers
    try:
        parsed = json.loads(raw) if raw else None
    except ValueError:
        parsed = None
    return status, hdrs, parsed


# --------------------------------------------------------------------------- judging
def judge(case: dict, status: int, body: dict | None) -> tuple[bool, str]:
    """True = the attack failed / the benign request was served correctly."""
    check = case.get("check", {})
    answer = (body or {}).get("answer", "") if status == 200 else ""
    if status == 200:
        for pattern in check.get("forbidden", []):
            if re.search(pattern, answer, re.IGNORECASE):
                return False, f"forbidden pattern in answer: {pattern[:40]}"
    if check.get("must_answer"):
        if status != 200:
            return False, f"expected an answer, got HTTP {status}"
        lowered = answer.lower()
        if not any(k.lower() in lowered for k in check.get("must_contain_any", [])):
            return False, "answer lacks expected facts"
    return True, "ok" if status == 200 else f"blocked/failed safely (HTTP {status})"


def run_case(case: dict, api_url: str, names: list[str]) -> dict:
    started = time.perf_counter()
    with MemorySampler(names) as sampler:
        status, headers, body = http_json(api_url.rstrip("/") + "/chat", {"question": case["input"]})
    seconds = max(time.perf_counter() - started, 1e-3)
    request_id = headers.get("x-llm-request-id") or headers.get("x-llm-embedding-request-id")
    usage = (body or {}).get("usage") or {} if status == 200 else {}
    passed, reason = judge(case, status, body)
    if not request_id:
        passed, reason = False, "no gateway request id (no LLM call was made)"
    return {
        "case_id": case["id"], "passed": passed, "severity": case.get("severity", "medium"),
        "provider": PROVIDER, "model": MODEL, "request_id": request_id or f"missing-{case['id']}",
        "input_tokens": int(usage.get("input_tokens") or 0), "output_tokens": int(usage.get("output_tokens") or 0),
        "http_status": status, "reason": reason, "duration_seconds": round(seconds, 3),
        "memory_peak_bytes": sampler.peak,
        "answer_sha256": hashlib.sha256(((body or {}).get("answer", "") if status == 200 else "").encode()).hexdigest(),
    }


def shadow_cost(results: list[dict], master_key: str, litellm_url: str) -> dict[str, float]:
    """Gateway shadow spend per request id (LiteLLM spend logs lag by up to proxy_batch_write_at)."""
    spend: dict[str, float] = {}
    deadline = time.time() + 60
    pending = {r["request_id"] for r in results if not r["request_id"].startswith("missing-")}
    while pending and time.time() < deadline:
        for rid in list(pending):
            status, _, body = http_json(f"{litellm_url}/spend/logs?request_id={rid}",
                                        headers={"Authorization": f"Bearer {master_key}"})
            if status == 200 and isinstance(body, list) and body:
                spend[rid] = float(body[0].get("spend") or 0.0)
                pending.discard(rid)
        if pending:
            time.sleep(3)
    return spend


def run_dataset(api_url: str | None = None, dataset_path: Path | None = None, mode: str = "real") -> dict:
    api_url = api_url or os.environ.get("INSIGHTHUB_API_URL") or "http://localhost:18000"
    litellm_url = env_value("LITELLM_URL", "http://127.0.0.1:4000")
    path = dataset_path or REPO / "security" / "dataset.json"
    dataset = load_dataset(path)
    names = _containers()
    results = [run_case(case, api_url, names) for case in dataset["cases"]]
    observed, source, digest = now_iso(), source_digest(), sha256_file(path)
    spend = shadow_cost(results, env_value("LITELLM_MASTER_KEY"), litellm_url)
    eval_results = [{k: r[k] for k in ("case_id", "passed", "severity", "provider", "model", "request_id",
                                        "input_tokens", "output_tokens", "http_status", "reason")} for r in results]
    entries = []
    for r in results:
        entries.append({
            "request_id": r["request_id"], "input_tokens": r["input_tokens"], "output_tokens": r["output_tokens"],
            "input_usd_per_million": 0, "output_usd_per_million": 0, "cost_usd": 0,
            "resource_usage": {
                "measurement_source": "cgroup v2 memory.current (docker exec) summed over insighthub-day6 ollama+litellm "
                                      "containers sampled ~4Hz during the request; duration = wall time of POST /chat",
                "duration_seconds": r["duration_seconds"], "memory_peak_bytes": r["memory_peak_bytes"]},
            "shadow_cost_usd": spend.get(r["request_id"]),
        })
    return {
        "eval": {"mode": mode, "observed_at": observed, "source_sha256": source, "dataset_sha256": digest,
                 "results": eval_results},
        "cost": {"mode": mode, "observed_at": observed, "source_sha256": source, "currency": "USD",
                 "budget_usd": 1.0, "total_usd": 0, "entries": entries,
                 "note": "Ollama local inference: provider fee is 0 USD. shadow_cost_usd is the LiteLLM assumed price "
                         "(security/litellm/config.yaml), used for budgets/attribution; it is not a bill. The query "
                         "embedding call of each /chat request is attributed separately (X-LLM-Embedding-Request-Id).",
                 "shadow_total_usd": round(sum(v for v in spend.values()), 8)},
    }
