#!/usr/bin/env bash
# Shared helpers for the Day 4 chaos scripts. Sourced, never executed directly.
# Fault state lives in annotations on the target object so --revert needs no local file.
set -euo pipefail

CTX="${KUBE_CONTEXT:-kind-insighthub-lab}"
NS="${NAMESPACE:-insighthub-local}"
API_URL="${API_URL:-http://localhost:8000}"
PROM_URL="${PROMETHEUS_URL:-http://localhost:9090}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SAMPLE_DOC="${SAMPLE_DOC:-$REPO_ROOT/sample-docs/so-tay-van-hanh.md}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/evidence}"
ANN="chaos.insighthub.io"

k() { kubectl --context "$CTX" -n "$NS" "$@"; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '[%s] %s\n' "$(now_utc)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# NFR 8.3 #1: do not inject before >=1h of baseline exists (spec pitfall 8.7).
# 120 scrapes at 30s = 1h; allow a little slack for missed scrapes. Summed over all series:
# every pod replacement (rollout, chaos revert) starts a new `up` series with its own count.
require_baseline() {
  [ "${SKIP_BASELINE_CHECK:-0}" = 1 ] && { log "WARNING: baseline check skipped"; return 0; }
  local n
  n=$(curl -sG "$PROM_URL/api/v1/query" --data-urlencode \
      'query=sum(count_over_time(up{job="insighthub-api"}[3h]))' \
      | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(int(float(r[0]["value"][1])) if r else 0)') \
      || die "Prometheus unreachable at $PROM_URL"
  [ "$n" -ge 115 ] || die "baseline too short: $n scrapes of up{job=insighthub-api} (~$((n/2)) min); need >=115 (1h). Use --skip-baseline-check to override knowingly."
  log "baseline ok: $n scrapes (~$((n/2)) min)"
}

annotate() { k annotate --overwrite "$1" "$ANN/$2=$3" >/dev/null; }
annotation() { k get "$1" -o "jsonpath={.metadata.annotations.$(echo "$ANN" | sed 's/\./\\./g')/$2}"; }
clear_annotation() { k annotate "$1" "$ANN/$2-" >/dev/null 2>&1 || true; }

# Unique upload each call so content-hash idempotency never swallows the request.
# Prints the HTTP status code.
upload_unique() {
  local tmp status
  tmp=$(mktemp --suffix=.md)
  { cat "$SAMPLE_DOC"; printf '\n\nchaos marker %s %s\n' "$RANDOM" "$(date +%s%N)"; } > "$tmp"
  status=$(curl -s -o /dev/null -w '%{http_code}' -m 20 -X POST "$API_URL/documents" \
           -F "file=@${tmp};filename=chaos-$(date +%s%N).md;type=text/markdown" || true)
  rm -f "$tmp"; echo "${status:-000}"
}

chat_once() {
  curl -s -o /dev/null -w '%{http_code}' -m 60 -X POST "$API_URL/chat" \
    -H 'Content-Type: application/json' \
    -d '{"question":"InsightHub có những thành phần chính nào?"}' || echo 000
}

# Record the incident window for RCA authoring (evidence/ is outside the source fingerprint).
write_window() { # name start fault_end end
  mkdir -p "$EVIDENCE_DIR"
  python3 - "$EVIDENCE_DIR/chaos-$1-window.json" "$2" "$3" "$4" <<'PY'
import json, sys
path, start, fault_end, end = sys.argv[1:5]
json.dump({"started_at": start, "fault_removed_at": fault_end, "ended_at": end}, open(path, "w"), indent=2)
print(path)
PY
}

# Delete leftovers created by the chaos uploads (filename prefix chaos-).
cleanup_chaos_docs() {
  local ids id
  ids=$(curl -s -m 20 "$API_URL/documents" | python3 -c '
import json, sys
try: docs = json.load(sys.stdin)
except Exception: docs = []
docs = docs.get("items", docs) if isinstance(docs, dict) else docs
print(" ".join(str(d["id"]) for d in docs if str(d.get("filename","")).startswith("chaos-")))') || true
  for id in $ids; do curl -s -o /dev/null -m 10 -X DELETE "$API_URL/documents/$id" || true; done
  log "removed $(echo "$ids" | wc -w) chaos-* documents"
}
