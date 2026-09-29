"""ARQ job entrypoint. Reuses api's synchronous ingestion pipeline unchanged."""

import asyncio
import json
import logging
from datetime import datetime, timezone

from arq import Retry

from app.core.db import get_conn
from app.core.errors import (
    DocumentConflict,
    DocumentNotFound,
    ProviderError,
    SchemaMismatch,
)
from app.services.ingestion import process_document

logger = logging.getLogger("insighthub.worker")

# scripts/VERIFICATION_CONTRACT.md (Day 1) fetches container logs and expects the
# ingestion_completed event as one standalone, parseable JSON line. A dedicated
# logger + handler keeps it free of the "%(levelname)s:%(name)s:" prefix that the
# default logging config would otherwise prepend to `logger`'s messages.
_event_logger = logging.getLogger("insighthub.worker.events")
_event_logger.propagate = False
_event_logger.setLevel(logging.INFO)
if not _event_logger.handlers:
    _event_handler = logging.StreamHandler()
    _event_handler.setFormatter(logging.Formatter("%(message)s"))
    _event_logger.addHandler(_event_handler)


def _log_ingestion_completed(document_id: int) -> None:
    _event_logger.info(
        json.dumps(
            {
                "event": "ingestion_completed",
                "document_id": document_id,
                "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "status": "ready",
            }
        )
    )


# process_document blocks on psycopg + provider HTTP calls; run it in a thread so it
# never stalls arq's event loop (and the other jobs it may be running concurrently).
PROVIDER_RETRY_BASE_SECONDS = 2


def _mark_failed_if_still_pending(document_id: int, error_code: str) -> None:
    """DocumentNotFound/DocumentConflict/SchemaMismatch/job-timeout can all leave
    process_document's own transaction without ever writing a status, so without this
    the row stays 'pending' forever and MH7 (ready/failed within 30s) is violated. The
    status='pending' guard is a no-op if a concurrent/earlier attempt already
    committed ready or failed.
    """
    with get_conn() as conn:
        conn.execute(
            "UPDATE documents SET status = 'failed', chunk_count = 0, "
            "embedding_identity_id = NULL, error_code = %s "
            "WHERE id = %s AND status = 'pending'",
            (error_code, document_id),
        )


async def ingest_document(
    ctx: dict, document_id: int, filename: str, content: bytes
) -> int:
    try:
        chunk_count = await asyncio.to_thread(
            process_document, document_id, filename, content
        )
    except ProviderError:
        # Transient embedding-provider failure: process_document already recorded
        # status=failed/error_code=provider_error, so a retry safely reprocesses via
        # the existing content_sha256 + pipeline_id idempotency check.
        job_try = ctx["job_try"]
        defer = PROVIDER_RETRY_BASE_SECONDS**job_try
        logger.warning(
            "ingestion job retrying after provider error: document_id=%s try=%s defer=%ss",
            document_id,
            job_try,
            defer,
        )
        raise Retry(defer=defer) from None
    except (DocumentNotFound, DocumentConflict, SchemaMismatch) as exc:
        logger.warning(
            "ingestion job failed before process_document recorded a status: "
            "document_id=%s code=%s",
            document_id,
            exc.code,
        )
        _mark_failed_if_still_pending(document_id, exc.code)
        raise
    except asyncio.CancelledError:
        # arq cancels this job's task when it runs past WorkerSettings.job_timeout
        # (see settings.py). asyncio.to_thread cannot actually stop process_document's
        # underlying thread, but the document must not stay stuck at "pending" just
        # because the job wrapper got cancelled here. CancelledError is a
        # BaseException, not an Exception, so it would otherwise skip every except
        # clause below and leave the row untouched.
        logger.warning(
            "ingestion job timed out: document_id=%s try=%s",
            document_id,
            ctx["job_try"],
        )
        _mark_failed_if_still_pending(document_id, "timeout")
        raise
    except Exception:
        logger.warning("ingestion job failed: document_id=%s", document_id)
        raise
    else:
        _log_ingestion_completed(document_id)
        return chunk_count
