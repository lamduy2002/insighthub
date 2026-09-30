"""Untrusted-document defenses (injection layer 1 and 2).

Documents are data. Paragraphs that try to give instructions to the AI assistant are neutralized at
ingestion time (before chunking and embedding) and filtered again at retrieval time for chunks that were
indexed before this defense existed. Heuristics are deliberately conservative and paragraph-scoped; they are
one layer of defense in depth, not a proof (see security/threat-model.md).
"""

import logging
import re

logger = logging.getLogger("insighthub.sanitize")

REMOVED_MARKER = "[Đoạn bị loại bỏ: chứa chỉ dẫn nhằm điều khiển trợ lý AI]"

_PATTERNS = [
    r"ignore\s+(?:all\s+|any\s+|the\s+)?(?:previous|prior|above|earlier)\s+(?:instructions?|prompts?|rules)",
    r"disregard\s+(?:all\s+|any\s+|the\s+|your\s+)?(?:previous|prior|above|earlier)?\s*(?:instructions?|rules)",
    r"forget\s+(?:all\s+|your\s+)?(?:previous\s+)?instructions",
    r"note\s+for\s+the\s+ai(?:\s+assistant)?",
    r"(?:message|instruction)s?\s+(?:for|to)\s+the\s+(?:ai|assistant|llm|model)",
    r"you\s+are\s+now\s+(?:in\s+)?(?:a\s+|an\s+)?[\w\s-]{0,30}mode",
    r"(?:reveal|print|show|display|repeat|output)\b.{0,50}\b(?:system\s+prompt|environment\s+variables?|api\s+keys?|secrets?)",
    r"respond\s+only\s+with\s+the\s+text",
    r"when\s+any\s+user\s+asks\s+any\s+question",
    r"bỏ\s+qua\s+(?:mọi|tất\s+cả|các)?\s*(?:hướng\s+dẫn|chỉ\s+dẫn|chỉ\s+thị|lệnh)\s+(?:trước|ở\s+trên|trước\s+đó)",
    r"chế\s+độ\s+bảo\s+trì",
    r"(?:tiết\s+lộ|hiển\s+thị|in\s+ra)\b.{0,50}\b(?:system\s+prompt|biến\s+môi\s+trường|khóa\s+api|chỉ\s+dẫn\s+hệ\s+thống)",
]
_INJECTION = re.compile("|".join(f"(?:{p})" for p in _PATTERNS), re.IGNORECASE | re.DOTALL)
_PARAGRAPH_BREAK = re.compile(r"\n\s*\n")


def looks_like_injection(text: str) -> bool:
    return bool(_INJECTION.search(text))


def sanitize_untrusted_text(text: str) -> tuple[str, int]:
    """Replace every paragraph that contains assistant-directed instructions; return (text, removed)."""
    removed = 0
    paragraphs = []
    for paragraph in _PARAGRAPH_BREAK.split(text):
        if looks_like_injection(paragraph):
            removed += 1
            paragraphs.append(REMOVED_MARKER)
        else:
            paragraphs.append(paragraph)
    return "\n\n".join(paragraphs), removed


def drop_suspicious_contexts(contexts: list[dict]) -> tuple[list[dict], int]:
    """Retrieval-time filter for chunks indexed before sanitization (or that slipped through)."""
    kept = [c for c in contexts if not looks_like_injection(c["chunk_text"])]
    dropped = len(contexts) - len(kept)
    if dropped:
        logger.warning('{"event": "retrieval_chunks_dropped", "count": %d}', dropped)
    return kept, dropped
