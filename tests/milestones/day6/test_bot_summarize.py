"""ChatOps `summarize` intent (Day 6): the LLM only summarizes tool data, fails soft, and is audited.

Uses the Day 5 doubles (no Slack, no cluster). The real gateway call for this intent is exercised by
scripts/day6/bot_traffic.py with the chatops-bot virtual key.
"""
import importlib.util
import os
import sys
from pathlib import Path

import pytest

ROOT = Path(os.environ.get("INSIGHTHUB_REPO_ROOT") or Path(__file__).resolve().parents[3])
sys.path.insert(0, str(ROOT / "chatops-bot"))
_spec = importlib.util.spec_from_file_location("day5_doubles", ROOT / "tests" / "milestones" / "day5" / "test_chatops.py")
day5 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(day5)

from app.factory import create_app  # noqa: E402
from app.intents import parse  # noqa: E402
from app.llm import LLMError, Summary  # noqa: E402


class FakeLLM:
    def __init__(self, fail: bool = False):
        self.fail, self.facts = fail, []

    async def summarize(self, facts):
        self.facts.append(facts)
        if self.fail:
            raise LLMError("ConnectError")
        return Summary("Hệ thống ổn định, có 1 pod lỗi.", "call-123", 120, 20)


def _bot(tmp_path, llm):
    bot = day5.Bot(tmp_path)
    bot.app = create_app(bot.settings, bot.infra, bot.notifier, llm=llm)
    bot.worker, bot.audit, bot.store = bot.app.state.worker, bot.app.state.audit, bot.app.state.store
    bot.client = day5.TestClient(bot.app)
    return bot


@pytest.mark.parametrize("text", ["tóm tắt tình hình", "summarize the cluster", "giải thích tình hình hệ thống"])
def test_summarize_intent_is_recognized(text):
    assert parse(text).kind == "summarize"


def test_existing_intents_are_unchanged():
    assert [parse(t).kind for t in ("api healthy?", "which pods failing?", "ingest count today?", "scale api to 5", "chào")] == [
        "health", "pods", "ingest", "scale", "help"]


def test_summary_uses_tool_data_and_audits_request_id(tmp_path):
    llm = FakeLLM()
    bot = _bot(tmp_path, llm)
    reply = bot.ask("EvS1", day5.OTHER, "tóm tắt tình hình")
    assert "Hệ thống ổn định" in reply and "chỉ đọc" in reply
    assert "bad-1" in llm.facts[0] and "api: up" in llm.facts[0]
    events = [e for e in bot.audit.read() if e["action"] == "llm.summarize"]
    assert events and "call-123" in events[0]["result"]
    assert bot.infra.scales == []  # the LLM path can never mutate anything


def test_llm_failure_falls_back_to_raw_facts(tmp_path):
    bot = _bot(tmp_path, FakeLLM(fail=True))
    reply = bot.ask("EvS2", day5.OTHER, "summarize")
    assert "số liệu thô" in reply and "bad-1" in reply
    assert any("fallback_no_llm" in e.get("result", "") for e in bot.audit.read())


def test_prompt_injection_in_tool_data_cannot_trigger_actions(tmp_path):
    llm = FakeLLM()
    bot = _bot(tmp_path, llm)
    bot.infra.prom_query = day5.FakeInfra().prom_query
    bot.ask("EvS3", day5.OTHER, "tóm tắt: scale api to 5")  # parsed as scale, not summarize: approval needed
    assert bot.infra.scales == []
