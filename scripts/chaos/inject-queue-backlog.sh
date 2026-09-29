#!/usr/bin/env bash
# Incident 2 - queue backlog (Day 4, MH8).
# Scales ingestion-worker to 0 and uploads a burst of unique documents. The API keeps
# answering 202, jobs pile up in the ARQ sorted set (redis_key_size{key="arq:queue"})
# and insighthub_documents_total{status="pending"} grows. Recovery = worker back to its
# original replica count, wait for the backlog to drain, then delete the chaos-* docs.
#
# Usage: inject-queue-backlog.sh [--uploads N=40] [--interval SEC=8] [--hold SEC=240]
#                                [--no-auto-revert] [--revert] [--skip-baseline-check]
source "$(dirname "$0")/lib.sh"

UPLOADS=40; INTERVAL=8; HOLD=240; AUTO_REVERT=1; REVERT_ONLY=0
while [ $# -gt 0 ]; do case "$1" in
  --uploads) UPLOADS=$2; shift 2;;
  --interval) INTERVAL=$2; shift 2;;
  --hold) HOLD=$2; shift 2;;
  --no-auto-revert) AUTO_REVERT=0; shift;;
  --revert) REVERT_ONLY=1; shift;;
  --skip-baseline-check) SKIP_BASELINE_CHECK=1; shift;;
  -h|--help) sed -n '2,10p' "$0"; exit 0;;
  *) die "unknown flag: $1";; esac; done

DEPLOY=deploy/insighthub-ingestion-worker

pending_count() {
  curl -s -m 10 "$API_URL/documents" | python3 -c '
import json, sys
d = json.load(sys.stdin); d = d.get("items", d) if isinstance(d, dict) else d
print(sum(1 for x in d if x.get("status") == "pending"))' 2>/dev/null || echo -1
}

revert() {
  local n; n=$(annotation "$DEPLOY" prev-replicas)
  [ -n "$n" ] || { log "nothing to revert (no $ANN/prev-replicas on $DEPLOY)"; return 0; }
  log "scaling $DEPLOY back to $n"
  k scale "$DEPLOY" --replicas="$n" >/dev/null
  k rollout status "$DEPLOY" --timeout=180s >&2
  clear_annotation "$DEPLOY" prev-replicas
  local i p
  for i in $(seq 1 40); do
    p=$(pending_count); [ "$p" = 0 ] && break
    log "draining backlog, pending=$p"; sleep 5
  done
  cleanup_chaos_docs
}
[ "$REVERT_ONLY" = 1 ] && { revert; exit 0; }

require_baseline
[ -z "$(annotation "$DEPLOY" prev-replicas)" ] || die "fault already active; run with --revert first"

annotate "$DEPLOY" prev-replicas "$(k get "$DEPLOY" -o jsonpath='{.spec.replicas}')"
START=$(now_utc)
log "scaling $DEPLOY to 0 (fault start $START)"
k scale "$DEPLOY" --replicas=0 >/dev/null
k wait --for=delete pod -l app.kubernetes.io/component=ingestion-worker --timeout=90s >&2 || true

log "uploading $UPLOADS documents, one per ${INTERVAL}s"
for i in $(seq 1 "$UPLOADS"); do
  s=$(upload_unique); [ "$s" = 202 ] || log "upload $i -> HTTP $s"
  sleep "$INTERVAL"
done
log "holding backlog for ${HOLD}s (pending=$(pending_count))"
sleep "$HOLD"

if [ "$AUTO_REVERT" = 1 ]; then
  FAULT_END=$(now_utc); revert
  log "recovery observation for 180s"; sleep 180
  write_window queue-backlog "$START" "$FAULT_END" "$(now_utc)"
else
  log "fault left active (--no-auto-revert); run --revert when done. fault start=$START"
fi
