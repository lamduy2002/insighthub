"""Explicit fixture or real embeddings. Never reshape a provider vector."""

import hashlib
import math

from app.core.config import get_settings
from app.core.errors import ProviderError
from app.core.metrics import record_embedding_usage
from app.core.providers import indexed_embeddings, post_json, token_count


def _local_embed(texts: list[str], dim: int) -> list[list[float]]:
    """Deterministic finite fixtures; no semantic retrieval quality claim."""
    vectors = []
    for text in texts:
        raw = hashlib.shake_256(text.encode("utf-8")).digest(dim * 2)
        vector = [
            (int.from_bytes(raw[i : i + 2], "big") - 32767.5) / 32767.5
            for i in range(0, len(raw), 2)
        ]
        norm = math.hypot(*vector)
        vectors.append([value / norm for value in vector])
    return vectors


def validate_vectors(vectors, expected_count: int, dim: int) -> list[list[float]]:
    if not isinstance(vectors, (list, tuple)) or len(vectors) != expected_count:
        raise ProviderError()
    result = []
    for vector in vectors:
        if not isinstance(vector, (list, tuple)) or len(vector) != dim:
            raise ProviderError()
        if any(type(value) not in (int, float) for value in vector):
            raise ProviderError()
        try:
            values = [float(value) for value in vector]
            if any(
                not math.isfinite(value) or abs(value) > 3.402823466e38
                for value in values
            ):
                raise ProviderError()
            norm = math.hypot(*values)
        except (OverflowError, ValueError):
            raise ProviderError() from None
        if not math.isfinite(norm) or norm == 0:
            raise ProviderError()
        result.append([value / norm for value in values])
    return result


def _gemini_embed(texts, input_type, settings):
    model = settings.resolved_embedding_model
    requests = []
    for text in texts:
        config = {"outputDimensionality": settings.embedding_dim}
        if model == "gemini-embedding-001":
            config["taskType"] = (
                "RETRIEVAL_QUERY" if input_type == "query" else "RETRIEVAL_DOCUMENT"
            )
        else:
            text = (
                f"task: question answering | query: {text}"
                if input_type == "query"
                else f"title: none | text: {text}"
            )
        requests.append(
            {
                "model": f"models/{model}",
                "content": {"parts": [{"text": text}]},
                "embedContentConfig": config,
            }
        )
    # Separate requests avoid Gemini 2's multi-input aggregation semantics.
    data = post_json(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:batchEmbedContents",
        headers={"x-goog-api-key": settings.gemini_api_key},
        payload={"requests": requests},
    )
    # Gemini can report batch usage; preserve it for Day 4/6 token accounting.
    usage = data.get("usageMetadata") or {}
    tokens = (
        token_count(usage.get("promptTokenCount")) if isinstance(usage, dict) else None
    )
    return [item["values"] for item in data["embeddings"]], tokens


def _real_embed(texts, input_type, settings):
    provider = settings.embedding_provider
    model = settings.resolved_embedding_model
    if provider == "gemini":
        return _gemini_embed(texts, input_type, settings)
    if provider == "openai":
        data = post_json(
            settings.openai_base_url.rstrip("/") + "/embeddings",
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "x-litellm-tags": f"app:insighthub,purpose:embedding-{input_type}",
            },
            payload={
                "model": model,
                "input": texts,
                "dimensions": settings.embedding_dim,
                "encoding_format": "float",
            },
        )
        return indexed_embeddings(data, len(texts)), token_count(
            (data.get("usage") or {}).get("prompt_tokens")
        )
    if provider == "voyage":
        data = post_json(
            "https://api.voyageai.com/v1/embeddings",
            headers={"Authorization": f"Bearer {settings.voyage_api_key}"},
            payload={
                "model": model,
                "input": texts,
                "input_type": input_type,
                "output_dimension": settings.embedding_dim,
                "truncation": False,
            },
        )
        return indexed_embeddings(data, len(texts)), token_count(
            (data.get("usage") or {}).get("total_tokens")
        )
    if provider == "ollama":
        inputs = [
            f"Represent this sentence for searching relevant passages: {text}"
            if input_type == "query"
            else text
            for text in texts
        ]
        data = post_json(
            settings.ollama_base_url.rstrip("/") + "/api/embed",
            headers={},
            payload={"model": model, "input": inputs, "truncate": False},
        )
        return data["embeddings"], token_count(data.get("prompt_eval_count"))
    raise ProviderError()


def embed(texts: list[str], input_type: str = "document") -> list[list[float]]:
    if input_type not in {"query", "document"}:
        raise ValueError("input_type must be query or document")
    if any(not isinstance(text, str) or not text.strip() for text in texts):
        raise ValueError("Embedding inputs must be nonempty text")
    if not texts:
        return []
    settings = get_settings()
    vectors = []
    for start in range(0, len(texts), settings.embedding_batch_size):
        batch = texts[start : start + settings.embedding_batch_size]
        try:
            if settings.rag_mode == "fixture":
                raw, tokens = _local_embed(batch, settings.embedding_dim), None
            else:
                raw, tokens = _real_embed(batch, input_type, settings)
            record_embedding_usage(
                settings.embedding_provider, input_type, tokens, batch
            )
            vectors.extend(validate_vectors(raw, len(batch), settings.embedding_dim))
        except ProviderError:
            raise
        except (KeyError, TypeError, ValueError, AttributeError, IndexError):
            raise ProviderError() from None
    return vectors
