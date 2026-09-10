# InsightHub ingestion worker - multi-stage Dockerfile.
# Build context is the repo root (see docker-compose.yml) so app/ can be reused from api/
# unchanged, per AGENTS.md: "Tái sử dụng logic chunk/embed... không viết lại từ đầu."
FROM python:3.12.14-slim@sha256:78387bc3881b8273120a12ebe6c1ab22b018ccc2c9adf565ae1ac9b536e184ea AS base
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app

FROM base AS deps
COPY ingestion-worker/requirements.txt .
RUN pip install --no-cache-dir --require-hashes -r requirements.txt

FROM base AS runtime
# Non-root user
RUN groupadd --system --gid 1001 appuser \
    && useradd --system --uid 1001 --gid appuser appuser
COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin
COPY --chown=appuser:appuser api/app ./app
COPY --chown=appuser:appuser ingestion-worker/worker ./worker
USER appuser
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD arq --check worker.settings.WorkerSettings || exit 1
CMD ["arq", "worker.settings.WorkerSettings"]
