"""Create the four LiteLLM virtual keys and store them in the untracked .env (never printed)."""
import json
import os
import urllib.request
from pathlib import Path

ENV = Path(__file__).resolve().parents[2] / ".env"
BASE = os.environ.get("LITELLM_URL", "http://127.0.0.1:4000")
# alias -> (env var, max_budget in shadow USD, allowed models)
KEYS = {
    "insighthub": ("OPENAI_API_KEY", 1.2, ["chat-small", "embed-mxbai"]),
    "chatops-bot": ("LITELLM_KEY_CHATOPS_BOT", 0.3, ["chat-small"]),
    "coding-workflow": ("LITELLM_KEY_CODING_WORKFLOW", 0.5, ["chat-small"]),
}


def load_env() -> dict[str, str]:
    values = {}
    for line in ENV.read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            values[k] = v
    return values


def call(master: str, path: str, body: dict) -> dict:
    req = urllib.request.Request(BASE + path, json.dumps(body).encode(),
                                 {"Authorization": f"Bearer {master}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def main() -> None:
    env = load_env()
    for alias, (var, budget, models) in KEYS.items():
        if env.get(var, "").startswith("sk-"):
            print(f"skip {alias}: {var} already set")
            continue
        out = call(env["LITELLM_MASTER_KEY"], "/key/generate",
                   {"key_alias": alias, "max_budget": budget, "models": models,
                    "metadata": {"workload": alias, "budget_unit": "shadow-usd"}})
        env[var] = out["key"]
        print(f"created {alias}: budget={budget} models={models}")
    ENV.write_text("\n".join(f"{k}={v}" for k, v in env.items()) + "\n")
    ENV.chmod(0o600)


if __name__ == "__main__":
    main()
