#!/usr/bin/env python3
"""Delete every document and re-upload sample-docs/ (so the current ingestion code re-indexes them)."""
import json
import sys
import time
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
api = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:18000").rstrip("/")


def call(path, data=None, headers=None, method=None):
    req = urllib.request.Request(api + path, data=data, headers=headers or {}, method=method)
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


docs = call("/documents")
for d in docs if isinstance(docs, list) else docs.get("documents", []):
    call(f"/documents/{d['id']}", method="DELETE")
ids = []
for name in ("so-tay-van-hanh.md", "service-level-objectives.md", "huong-dan-nguoi-moi.md"):
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{name}\"\r\n"
            "Content-Type: text/markdown\r\n\r\n").encode() + (ROOT / "sample-docs" / name).read_bytes() \
        + f"\r\n--{boundary}--\r\n".encode()
    ids.append(call("/documents", body, {"Content-Type": f"multipart/form-data; boundary={boundary}"})["id"])
for _ in range(80):
    docs = call("/documents")
    docs = docs if isinstance(docs, list) else docs.get("documents", [])
    states = {d["id"]: d["status"] for d in docs}
    if all(states.get(i) in ("ready", "failed") for i in ids):
        break
    time.sleep(1.5)
print({d["filename"]: (d["status"], d["chunk_count"]) for d in docs})
