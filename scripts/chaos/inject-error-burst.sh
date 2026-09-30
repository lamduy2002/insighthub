#!/usr/bin/env bash
# Incident 3 - error burst (Day 4, MH9).
# Takes Redis down (StatefulSet -> 0). /readyz only checks the DB, so the API stays in
# rotation and /metrics keeps working, while POST /documents fails to enqueue and the
# metrics middleware records 5xx on that route. Redis here is emptyDir (queue/results
# only), so a restart loses in-flight jobs; the chaos-* documents are deleted on revert.
#
# Usage: inject-error-burst.sh [--uploads N=90] [--interval SEC=3] [--no-auto-revert]
#                              [--revert] [--skip-baseline-check]
source "$(dirname "$0")/lib.sh"

UPLOADS=90; INTERVAL=3; AUTO_REVERT=1; REVERT_ONLY=0
while [ $# -gt 0 ]; do case "$1" in
  --uploads) UPLOADS=$2; shift 2;;
  --interval) INTERVAL=$2; shift 2;;
  --no-auto-revert) AUTO_REVERT=0; shift;;
  --revert) REVERT_ONLY=1; shift;;
  --skip-baseline-check) SKIP_BASELINE_CHECK=1; shift;;
  -h|--help) sed -n '2,9p' "$0"; exit 0;;
  *) die "unknown flag: $1";; esac; done

TARGET=statefulset/insighthub-deps-redis

revert() {
  local n; n=$(annotation "$TARGET" prev-replicas)
  [ -n "$n" ] || { log "nothing to revert (no $ANN/prev-replicas on $TARGET)"; return 0; }
  log "scaling $TARGET back to $n"
  k scale "$TARGET" --replicas="$n" >/dev/null
  k rollout status "$TARGET" --timeout=180s >&2
  clear_annotation "$TARGET" prev-replicas
  cleanup_chaos_docs
}
[ "$REVERT_ONLY" = 1 ] && { revert; exit 0; }

require_baseline
[ -z "$(annotation "$TARGET" prev-replicas)" ] || die "fault already active; run with --revert first"

annotate "$TARGET" prev-replicas "$(k get "$TARGET" -o jsonpath='{.spec.replicas}')"
START=$(now_utc)
log "scaling $TARGET to 0 (fault start $START)"
k scale "$TARGET" --replicas=0 >/dev/null
k wait --for=delete pod/insighthub-deps-redis-0 --timeout=90s >&2 || true

log "uploading $UPLOADS documents, one per ${INTERVAL}s (expect 5xx)"
ok=0; bad=0
for i in $(seq 1 "$UPLOADS"); do
  s=$(upload_unique); case "$s" in 202) ok=$((ok+1));; *) bad=$((bad+1));; esac
  sleep "$INTERVAL"
done
log "uploads: $ok accepted, $bad failed"

if [ "$AUTO_REVERT" = 1 ]; then
  FAULT_END=$(now_utc); revert
  log "recovery observation for 180s"; sleep 180
  write_window error-burst "$START" "$FAULT_END" "$(now_utc)"
else
  log "fault left active (--no-auto-revert); run --revert when done. fault start=$START"
fi
