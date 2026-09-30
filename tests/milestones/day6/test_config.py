"""Static guarantees of the gateway/compose configuration (no network)."""
import os
import re
from pathlib import Path

import yaml

ROOT = Path(os.environ.get("INSIGHTHUB_REPO_ROOT") or Path(__file__).resolve().parents[3])
CONFIG = yaml.safe_load((ROOT / "security" / "litellm" / "config.yaml").read_text())


def test_guardrails_wrap_input_and_output_and_are_on_by_default():
    guards = {g["guardrail_name"]: g["litellm_params"] for g in CONFIG["guardrails"]}
    assert guards["injection-input"]["mode"] == "pre_call" and guards["injection-input"]["default_on"] is True
    assert guards["output-check"]["mode"] == "post_call" and guards["output-check"]["default_on"] is True
    categories = {c["category"] for c in guards["injection-input"]["categories"]}
    assert {"prompt_injection_jailbreak", "prompt_injection_system_prompt"} <= categories
    assert any("bỏ qua mọi hướng dẫn" in w["keyword"] for w in guards["injection-input"]["blocked_words"])


def test_gateway_models_are_priced_and_named_honestly():
    models = {m["model_name"]: m["litellm_params"] for m in CONFIG["model_list"]}
    assert {"chat-small", "embed-mxbai"} <= set(models)
    assert all(p["model"].startswith("ollama") and p["input_cost_per_token"] > 0 for p in models.values())
    names = " ".join(models) + " " + " ".join(p["model"] for p in models.values())
    assert not re.search(r"(?i)hash|extractive|fallback|fixture|mock|dummy|fake", names)


def test_no_secret_is_hardcoded_and_app_only_talks_to_the_gateway():
    text = (ROOT / "security" / "litellm" / "config.yaml").read_text() + (ROOT / "docker-compose.day6.yml").read_text()
    assert not re.search(r"sk-[A-Za-z0-9_-]{12,}", text)
    assert CONFIG["general_settings"]["master_key"] == "os.environ/LITELLM_MASTER_KEY"
    example = (ROOT / ".env.example").read_text()
    assert "LITELLM_MASTER_KEY=" in example and not re.search(r"LITELLM_MASTER_KEY=\S", example)
