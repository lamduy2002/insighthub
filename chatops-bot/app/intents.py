"""Rule-based intent parsing (no LLM). Vietnamese and English keywords, diacritics folded."""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from typing import Any

DEPLOYMENT_ALIASES = {
    "api": "insighthub-api",
    "worker": "insighthub-ingestion-worker",
    "ingestion-worker": "insighthub-ingestion-worker",
    "web": "insighthub-web",
}

_SLACK_FORMATTING = re.compile(r"[`*_~]")  # code, bold, italic, strike marks Slack keeps when text is copied
_MENTION = re.compile(r"<@[A-Z0-9]+(?:\|[^>]*)?>")
_CONFIRM = re.compile(r"^(?:confirm|xac nhan)\s+([a-z0-9_-]{6,32})$")
_SCALE = re.compile(r"\bscale\s+([a-z0-9-]+)\s+(?:to|len)\s+(-?\d+)\b")
_DESTRUCTIVE = re.compile(r"\b(delete|remove|xoa|drop|exec|rollout|secret|secrets|kubectl|rm)\b")


@dataclass(frozen=True)
class Intent:
    kind: str  # health | ingest | pods | summarize | scale | confirm | destructive | help
    args: dict[str, Any] = field(default_factory=dict)


def normalize(text: str) -> str:
    text = _SLACK_FORMATTING.sub("", _MENTION.sub(" ", text)).replace("đ", "d").replace("Đ", "D")
    folded = unicodedata.normalize("NFD", text)
    folded = "".join(c for c in folded if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", folded.lower()).strip(" ?!.\n\t")


def parse(text: str) -> Intent:
    clean = normalize(text)
    match = _CONFIRM.match(clean)
    if match:
        return Intent("confirm", {"token": match.group(1).upper()})
    match = _SCALE.search(clean)
    if match:
        name = match.group(1)
        return Intent("scale", {"deployment": DEPLOYMENT_ALIASES.get(name, name),
                                "replicas": int(match.group(2))})
    if _DESTRUCTIVE.search(clean):
        return Intent("destructive", {"text": clean[:80]})
    if "pod" in clean:
        return Intent("pods")
    if re.search(r"\b(ingest|ingestion|doc|docs|document|documents|tai lieu|upload)\b", clean):
        return Intent("ingest")
    if re.search(r"\b(health|healthy|khoe|status|song|on dinh)\b", clean):
        return Intent("health")
    if re.search(r"\b(tom tat|tinh hinh|summary|summarize|summarise|explain|giai thich)\b", clean):
        return Intent("summarize")
    return Intent("help")
