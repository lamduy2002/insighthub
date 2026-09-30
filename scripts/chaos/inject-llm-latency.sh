#!/usr/bin/env bash
# Incident 1 - LLM latency spike (Day 4, MH7).
#
# The lab runs RAG_MODE=fixture, where generate() is an instant extractive slice, and
# the config forbids mixing fixture/real providers (swapping embeddings would need a
# reindex, spec 0.4). So a real slow provider cannot be used. Instead this is fault
# injection with no repo change: a ConfigMap-mounted sitecustomize.py wraps
# app.services.llm.generate with a sleep, so insighthub_llm_call_latency_seconds sees a
# genuine wall-clock delay. Root cause in the RCA must be described as injected delay.
#
# Usage: inject-llm-latency.sh [--delay SEC=4] [--duration SEC=420] [--no-auto-revert]
#                              [--revert] [--skip-baseline-check]
# Reverts with `kubectl rollout undo` to the revision recorded before injection.
source "$(dirname "$0")/lib.sh"

DELAY=4; DURATION=420; AUTO_REVERT=1; REVERT_ONLY=0
while [ $# -gt 0 ]; do case "$1" in
  --delay) DELAY=$2; shift 2;;
  --duration) DURATION=$2; shift 2;;
  --no-auto-revert) AUTO_REVERT=0; shift;;
  --revert) REVERT_ONLY=1; shift;;
  --skip-baseline-check) SKIP_BASELINE_CHECK=1; shift;;
  -h|--help) sed -n '2,15p' "$0"; exit 0;;
  *) die "unknown flag: $1";; esac; done

DEPLOY=deploy/insighthub-api

revert() {
  local rev; rev=$(annotation "$DEPLOY" prev-revision)
  [ -n "$rev" ] || { log "nothing to revert (no $ANN/prev-revision on $DEPLOY)"; return 0; }
  log "reverting $DEPLOY to revision $rev"
  k rollout undo "$DEPLOY" --to-revision="$rev" >/dev/null
  k rollout status "$DEPLOY" --timeout=180s >&2
  clear_annotation "$DEPLOY" prev-revision
  k delete configmap chaos-llm-latency --ignore-not-found >/dev/null
}
[ "$REVERT_ONLY" = 1 ] && { revert; exit 0; }

require_baseline
[ -z "$(annotation "$DEPLOY" prev-revision)" ] || die "fault already active; run with --revert first"

k create configmap chaos-llm-latency --dry-run=client -o yaml \
  --from-file=sitecustomize.py=/dev/stdin <<'PY' | k apply -f - >/dev/null
import importlib.abc, importlib.util, os, sys, time

_DELAY = float(os.environ.get("CHAOS_LLM_DELAY_SECONDS", "0"))
_TARGET = "app.services.llm"


class _Loader(importlib.abc.Loader):
    def __init__(self, inner):
        self._inner = inner

    def create_module(self, spec):
        return self._inner.create_module(spec)

    def exec_module(self, module):
        self._inner.exec_module(module)
        original = module.generate

        def slow_generate(*args, **kwargs):
            time.sleep(_DELAY)
            return original(*args, **kwargs)

        module.generate = slow_generate


class _Finder(importlib.abc.MetaPathFinder):
    def find_spec(self, name, path, target=None):
        if name != _TARGET or _DELAY <= 0:
            return None
        sys.meta_path.remove(self)
        try:
            spec = importlib.util.find_spec(name)
        finally:
            sys.meta_path.insert(0, self)
        if spec is None or spec.loader is None:
            return None
        spec.loader = _Loader(spec.loader)
        return spec


sys.meta_path.insert(0, _Finder())
PY

annotate "$DEPLOY" prev-revision "$(k get "$DEPLOY" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')"
START=$(now_utc)
log "injecting ${DELAY}s generate() delay into $DEPLOY (fault start $START)"
k patch "$DEPLOY" --type=strategic -p "$(cat <<JSON
{"spec":{"template":{"spec":{
 "volumes":[{"name":"chaos","configMap":{"name":"chaos-llm-latency"}}],
 "containers":[{"name":"api",
  "env":[{"name":"PYTHONPATH","value":"/chaos"},{"name":"CHAOS_LLM_DELAY_SECONDS","value":"$DELAY"}],
  "volumeMounts":[{"name":"chaos","mountPath":"/chaos","readOnly":true}]}]}}}}
JSON
)" >/dev/null
k rollout status "$DEPLOY" --timeout=180s >&2

log "driving /chat for ${DURATION}s"
END_AT=$(( $(date +%s) + DURATION ))
while [ "$(date +%s)" -lt "$END_AT" ]; do chat_once >/dev/null; sleep 2; done

if [ "$AUTO_REVERT" = 1 ]; then
  FAULT_END=$(now_utc); revert
  log "recovery traffic for 180s"
  R_END=$(( $(date +%s) + 180 ))
  while [ "$(date +%s)" -lt "$R_END" ]; do chat_once >/dev/null; sleep 5; done
  write_window llm-latency "$START" "$FAULT_END" "$(now_utc)"
else
  log "fault left active (--no-auto-revert); run --revert when done. fault start=$START"
fi
