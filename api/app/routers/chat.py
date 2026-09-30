"""RAG executes in FastAPI's threadpool; usage preserves its provenance."""

import time
from typing import Literal

from fastapi import APIRouter, HTTPException, Response
from pydantic import BaseModel, ConfigDict, Field

from app.core.errors import ServiceError
from app.core.metrics import llm_call_latency, llm_tokens_total, rag_query_latency
from app.core.providers import llm_calls
from app.services.llm import generate
from app.services.retrieval import retrieve

router = APIRouter(prefix="/chat", tags=["chat"])


class ChatRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    question: str = Field(min_length=1, max_length=2000)
    top_k: int | None = Field(default=None, ge=1, le=20)


class TokenUsage(BaseModel):
    input_tokens: int | None = None
    output_tokens: int | None = None
    source: Literal["provider", "unavailable"]


class ChatResponse(BaseModel):
    answer: str
    sources: list[str]
    contexts: list[dict]
    latency_ms: int
    mode: Literal["fixture", "real"]
    provider: str
    model: str
    usage: TokenUsage


def _attribution_headers(calls: list) -> dict:
    """Gateway call ids for cost attribution; absent when no gateway call happened."""
    headers = {}
    for path, call_id in calls:
        if not call_id:
            continue
        if path.endswith("/chat/completions"):
            headers["X-LLM-Request-Id"] = call_id
        elif path.endswith("/embeddings"):
            headers["X-LLM-Embedding-Request-Id"] = call_id
    return headers


@router.post("", response_model=ChatResponse)
def chat(req: ChatRequest, response: Response):
    start = time.perf_counter()
    calls: list = []
    llm_calls.set(calls)
    try:
        with rag_query_latency.time():
            contexts = retrieve(req.question, top_k=req.top_k)
            if not contexts:
                raise HTTPException(
                    404, "Chưa có tài liệu nào sẵn sàng. Hãy upload tài liệu trước."
                )
            with llm_call_latency.time():
                result = generate(req.question, contexts)
    except ServiceError as exc:
        exc.headers = _attribution_headers(calls)
        raise
    response.headers.update(_attribution_headers(calls))
    for direction in ("input", "output"):
        value = result["usage"].get(f"{direction}_tokens")
        if value is not None:
            llm_tokens_total.labels(result["provider"], direction).inc(value)
    return ChatResponse(
        **result,
        contexts=contexts,
        latency_ms=int((time.perf_counter() - start) * 1000),
    )
