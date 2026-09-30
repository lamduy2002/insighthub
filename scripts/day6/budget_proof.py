#!/usr/bin/env python3
"""Budget enforcement evidence (NFR #2, MH8): allowed/denied on each REAL virtual key, plus a concurrent burst on a
temporary key with the measured overshoot. Restores every real budget afterwards.
Writes evidence/day6-budget-proof.json. Needs LITELLM_MASTER_KEY and the four key variables in .env."""
import concurrent.futures as futures
import json
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "security" / "eval"))
import harness  # noqa: E402

URL = harness.env_value("LITELLM_URL", "http://127.0.0.1:4000")
MASTER = {"Authorization": "Bearer " + harness.env_value("LITELLM_MASTER_KEY")}
KEYS = {"insighthub": "OPENAI_API_KEY", "chatops-bot": "LITELLM_KEY_CHATOPS_BOT",
        "coding-workflow": "LITELLM_KEY_CODING_WORKFLOW", "promptfoo": "LITELLM_KEY_PROMPTFOO"}
TINY = {"model": "chat-small", "max_tokens": 8, "messages": [{"role": "user", "content": "Xin chào"}]}


def chat(key):
    status, headers, body = harness.http_json(URL + "/v1/chat/completions", TINY, {"Authorization": "Bearer " + key})
    return {"status": status, "request_id": headers.get("x-litellm-call-id"),
            "error": (json.dumps(body, ensure_ascii=False)[:220] if status != 200 else None)}


def info(key):
    return harness.http_json(f"{URL}/key/info?key={key}", headers=MASTER)[2]["info"]


def update(key, budget):
    harness.http_json(URL + "/key/update", {"key": key, "max_budget": budget}, MASTER)


report = {"observed_at": harness.now_iso(), "real_keys": {}, "note": "budget unit = LiteLLM shadow USD (Ollama has no fee)"}
for alias, var in KEYS.items():
    key = harness.env_value(var)
    before = info(key)
    allowed = chat(key)
    time.sleep(14)  # proxy_batch_write_at=10s
    after = info(key)
    original = after["max_budget"]
    update(key, round(after["spend"] * 0.5, 9))  # cap below current spend -> must be denied
    denied = chat(key)
    update(key, original)
    restored = info(key)["max_budget"]
    report["real_keys"][alias] = {"max_budget": original, "spend_before": before["spend"], "spend_after_allowed_call": after["spend"],
                                  "allowed_call": allowed, "denied_call_with_cap_below_spend": denied, "budget_restored": restored == original}
    print(alias, "allowed", allowed["status"], "denied", denied["status"], "restored", restored == original)

# Concurrent burst on a temporary key: how far can spend go past max_budget?
report["concurrency"] = []
for burst in (6, 12):
    budget = 2.5e-5
    key = harness.http_json(URL + "/key/generate", {"key_alias": f"proof-concurrent-{burst}-{uuid.uuid4().hex[:6]}",
                            "max_budget": budget, "models": ["chat-small"]}, MASTER)[2]["key"]
    started = time.time()
    with futures.ThreadPoolExecutor(max_workers=burst) as pool:
        results = list(pool.map(lambda _: chat(key), range(burst)))
    elapsed = round(time.time() - started, 2)
    time.sleep(14)
    spend = info(key)["spend"]
    follow_up = chat(key)
    harness.http_json(URL + "/key/delete", {"keys": [key]}, MASTER)
    row = {"parallel_requests": burst, "max_budget": budget, "allowed": sum(r["status"] == 200 for r in results),
           "denied": sum(r["status"] != 200 for r in results), "final_spend": spend, "overshoot": spend - budget,
           "overshoot_in_calls": round((spend - budget) / 1.1e-5, 2), "burst_seconds": elapsed,
           "spend_visible_after_seconds": 14, "follow_up_status": follow_up["status"]}
    report["concurrency"].append(row)
    print(row)
(ROOT / "evidence" / "day6-budget-proof.json").write_text(json.dumps(report, ensure_ascii=False, indent=1))
