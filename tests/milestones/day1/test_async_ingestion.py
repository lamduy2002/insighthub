"""Day 1 HTTP-only milestone tests: async ingestion via Redis + ARQ worker.

Exercises POST/GET/DELETE /documents and POST /chat over real HTTP against a
running `api` service - no direct database or process_document access.
Standard library only (urllib.request for multipart upload), matching
scripts/requirements-verification.in, which installs only pytest + PyYAML for
student milestone tests.

Set INSIGHTHUB_API_URL to point at a non-default api (defaults to
http://localhost:8000, the docker-compose default).

Function names below (test_async_upload, test_worker_ingests,
test_retry_idempotent, test_empty_input, test_duplicate_or_invalid,
test_refactor_regression) are the scenario names scripts/verify.py's day1
check requires by name.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
import uuid

import pytest

API_URL = os.environ.get("INSIGHTHUB_API_URL", "http://localhost:8000").rstrip("/")
READY_DEADLINE_SECONDS = 30.0
POLL_INTERVAL_SECONDS = 0.5
REQUEST_TIMEOUT_SECONDS = 10.0


def _multipart_body(filename: str, content: bytes) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    body = b"".join(
        [
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode(),
            b"Content-Type: text/plain\r\n\r\n",
            content,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
    return body, f"multipart/form-data; boundary={boundary}"


def _upload(filename: str, content: bytes) -> tuple[int, float, dict]:
    """POST /documents and return (status_code, elapsed_seconds, response_body)."""
    body, content_type = _multipart_body(filename, content)
    request = urllib.request.Request(
        f"{API_URL}/documents",
        data=body,
        method="POST",
        headers={"Content-Type": content_type},
    )
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(
            request, timeout=REQUEST_TIMEOUT_SECONDS
        ) as response:
            elapsed = time.perf_counter() - start
            return response.status, elapsed, json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        elapsed = time.perf_counter() - start
        return exc.code, elapsed, json.loads(exc.read().decode())


def _post_json(path: str, payload: dict) -> tuple[int, dict]:
    request = urllib.request.Request(
        f"{API_URL}{path}",
        data=json.dumps(payload).encode(),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(
            request, timeout=REQUEST_TIMEOUT_SECONDS
        ) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode())


def _list_documents() -> list[dict]:
    request = urllib.request.Request(f"{API_URL}/documents", method="GET")
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode())


def _find(documents: list[dict], document_id: int) -> dict | None:
    return next((doc for doc in documents if doc["id"] == document_id), None)


def _delete(document_id: int) -> int:
    request = urllib.request.Request(
        f"{API_URL}/documents/{document_id}", method="DELETE"
    )
    try:
        with urllib.request.urlopen(
            request, timeout=REQUEST_TIMEOUT_SECONDS
        ) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code  # best-effort cleanup; already-missing is not a fixture failure


def _poll_until_terminal(document_id: int, deadline: float = READY_DEADLINE_SECONDS) -> dict:
    """Poll GET /documents like a real client until the document leaves "pending"."""
    start = time.monotonic()
    last_seen: dict | None = None
    while time.monotonic() - start < deadline:
        document = _find(_list_documents(), document_id)
        if document is None:
            raise AssertionError(
                f"document {document_id} disappeared from GET /documents while polling"
            )
        last_seen = document
        if document["status"] != "pending":
            return document
        time.sleep(POLL_INTERVAL_SECONDS)
    raise AssertionError(
        f"document {document_id} still 'pending' after {deadline}s "
        f"(MH7 requires ready/failed within 30s); last seen: {last_seen}"
    )


def _unique_content(label: str) -> bytes:
    return f"InsightHub Day 1 milestone test content ({label}) {uuid.uuid4().hex}".encode()


@pytest.fixture
def uploaded_document_ids():
    """Tracks document ids created during a test so they get deleted afterward,
    keeping the shared database clean across repeated verifier runs.
    """
    ids: list[int] = []
    yield ids
    for document_id in ids:
        _delete(document_id)


def test_async_upload(uploaded_document_ids):
    """POST /documents must accept the upload and answer immediately (MH6: <1s),
    without blocking on ingestion - the document starts life as "pending" with
    zero chunks, since chunking/embedding now happens asynchronously in
    ingestion-worker rather than inline in the request handler.
    """
    content = _unique_content("upload-fast")
    status_code, elapsed, body = _upload("day1-upload-fast.txt", content)
    uploaded_document_ids.append(body["id"])

    assert status_code == 202, f"expected 202 Accepted, got {status_code}: {body}"
    assert elapsed < 1.0, f"POST /documents took {elapsed:.3f}s, must be < 1s (MH6)"
    assert body["status"] == "pending"
    assert body["chunk_count"] == 0


def test_worker_ingests(uploaded_document_ids):
    """After upload, ingestion-worker must dequeue the job, chunk + embed + store
    it, and flip status to "ready" with chunk_count > 0 - all within MH7's 30s
    SLA, observed purely by polling GET /documents like a real client would.
    """
    content = _unique_content("worker-ready")
    status_code, _, body = _upload("day1-worker-ready.txt", content)
    assert status_code == 202, f"expected 202 Accepted, got {status_code}: {body}"
    document_id = body["id"]
    uploaded_document_ids.append(document_id)

    document = _poll_until_terminal(document_id)

    assert document["status"] == "ready", (
        f"document {document_id} ended as '{document['status']}' "
        f"(error_code={document.get('error_code')}), expected 'ready'"
    )
    assert document["chunk_count"] > 0


def test_retry_idempotent(uploaded_document_ids):
    """Uploading the same content twice must produce two independent documents,
    each correctly and consistently chunked (no unexpected chunk duplication
    within either one). The API exposes no reprocess/retry endpoint for a single
    document_id, so this is the strongest idempotency signal reachable purely
    over HTTP; exact same-document_id retry idempotency (process_document called
    twice for the same id, no duplicate chunks) is covered separately by
    api/tests/test_integration.py's internal unit test, which has direct access
    to process_document and the database.
    """
    content = _unique_content("idempotency")

    first_status, _, first_body = _upload("day1-idempotency-a.txt", content)
    assert first_status == 202, f"expected 202 Accepted, got {first_status}: {first_body}"
    first_id = first_body["id"]
    uploaded_document_ids.append(first_id)

    second_status, _, second_body = _upload("day1-idempotency-b.txt", content)
    assert second_status == 202, f"expected 202 Accepted, got {second_status}: {second_body}"
    second_id = second_body["id"]
    uploaded_document_ids.append(second_id)

    assert first_id != second_id, "two uploads must create two independent documents"

    first_document = _poll_until_terminal(first_id)
    second_document = _poll_until_terminal(second_id)

    assert first_document["status"] == "ready", (
        f"document {first_id} ended as '{first_document['status']}' "
        f"(error_code={first_document.get('error_code')})"
    )
    assert second_document["status"] == "ready", (
        f"document {second_id} ended as '{second_document['status']}' "
        f"(error_code={second_document.get('error_code')})"
    )
    assert first_document["chunk_count"] > 0
    assert first_document["chunk_count"] == second_document["chunk_count"], (
        "identical content must be chunked identically and consistently - a "
        "mismatch would indicate nondeterministic or duplicated chunking"
    )


def test_empty_input(uploaded_document_ids):
    """Two "empty" shapes must both be rejected without ever reaching "ready":
    a zero-byte file is caught synchronously (422, no document even created),
    while a whitespace-only file passes the byte-count check but fails text
    extraction inside the worker, ending as status="failed" with an error_code -
    verified asynchronously, since that check now runs in ingestion-worker
    rather than inline in the request handler.
    """
    # Zero-byte file: rejected synchronously, before any document row exists.
    status_code, _, body = _upload("day1-empty-zero-bytes.txt", b"")
    assert status_code == 422, f"expected 422 for zero-byte upload, got {status_code}: {body}"

    # Whitespace-only file: accepted (202 pending), then the worker fails it.
    status_code, _, body = _upload("day1-empty-whitespace.txt", b"   \n\t  ")
    assert status_code == 202, f"expected 202 Accepted, got {status_code}: {body}"
    document_id = body["id"]
    uploaded_document_ids.append(document_id)

    document = _poll_until_terminal(document_id)
    assert document["status"] == "failed", (
        f"whitespace-only content must fail extraction, got status="
        f"'{document['status']}' (expected 'failed')"
    )
    assert document.get("error_code"), "a failed document must carry an error_code"


def test_duplicate_or_invalid(uploaded_document_ids):
    """Invalid: an unsupported file extension is rejected synchronously (400),
    before any document row is created. Duplicate: uploading the same filename
    twice, with different content each time, must not collide or get mixed up -
    each upload creates its own independent document that reaches "ready" with
    a chunk_count of its own.
    """
    # Invalid: unsupported extension.
    status_code, _, body = _upload("day1-invalid.exe", b"not a supported file type")
    assert status_code == 400, f"expected 400 for unsupported extension, got {status_code}: {body}"

    # Duplicate: same filename, different content each time.
    same_name = "day1-duplicate-name.txt"
    first_status, _, first_body = _upload(same_name, _unique_content("dup-a"))
    assert first_status == 202, f"expected 202 Accepted, got {first_status}: {first_body}"
    first_id = first_body["id"]
    uploaded_document_ids.append(first_id)

    second_status, _, second_body = _upload(same_name, _unique_content("dup-b"))
    assert second_status == 202, f"expected 202 Accepted, got {second_status}: {second_body}"
    second_id = second_body["id"]
    uploaded_document_ids.append(second_id)

    assert first_id != second_id, "same filename must still create two independent documents"

    first_document = _poll_until_terminal(first_id)
    second_document = _poll_until_terminal(second_id)
    assert first_document["status"] == "ready", (
        f"document {first_id} ended as '{first_document['status']}' "
        f"(error_code={first_document.get('error_code')})"
    )
    assert second_document["status"] == "ready", (
        f"document {second_id} ended as '{second_document['status']}' "
        f"(error_code={second_document.get('error_code')})"
    )
    assert first_document["chunk_count"] > 0
    assert second_document["chunk_count"] > 0


def test_refactor_regression(uploaded_document_ids):
    """The async refactor must not break the pre-existing document lifecycle and
    /chat contract: a document that becomes ready must be retrievable via RAG
    chat with its filename correctly attributed as a source, and deleting it
    must remove it from GET /documents - confirming upload, list, chat and
    delete all still work end-to-end after the sync -> async rewrite.
    """
    marker = uuid.uuid4().hex
    filename = "day1-refactor-regression.txt"
    content = f"InsightHub regression marker {marker} describes the async refactor.".encode()

    status_code, _, body = _upload(filename, content)
    assert status_code == 202, f"expected 202 Accepted, got {status_code}: {body}"
    document_id = body["id"]
    uploaded_document_ids.append(document_id)

    document = _poll_until_terminal(document_id)
    assert document["status"] == "ready", (
        f"document {document_id} ended as '{document['status']}' "
        f"(error_code={document.get('error_code')})"
    )

    chat_status, chat_body = _post_json("/chat", {"question": f"regression marker {marker}"})
    assert chat_status == 200, f"expected 200 from /chat, got {chat_status}: {chat_body}"
    assert chat_body.get("answer"), "chat response must include a non-empty answer"
    assert filename in chat_body.get("sources", []), (
        f"expected '{filename}' among chat sources, got {chat_body.get('sources')}"
    )

    delete_status = _delete(document_id)
    assert delete_status == 204, f"expected 204 from DELETE, got {delete_status}"
    uploaded_document_ids.remove(document_id)  # already deleted; skip fixture cleanup

    remaining = _list_documents()
    assert _find(remaining, document_id) is None, (
        f"document {document_id} must no longer appear in GET /documents after delete"
    )
