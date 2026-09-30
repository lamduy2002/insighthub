#!/usr/bin/env bash
# Adds the Day 6 "LLM Cost" dashboard as its own labelled ConfigMap (the Day 4 ConfigMap is untouched).
set -euo pipefail
CTX="${KUBE_CONTEXT:-kind-insighthub-lab}"
HERE="$(cd "$(dirname "$0")" && pwd)"
kubectl --context "$CTX" -n monitoring create configmap llm-cost-dashboard \
  --from-file="$HERE/llm-cost.json" --dry-run=client -o yaml \
  | kubectl --context "$CTX" label --local -f - grafana_dashboard=1 -o yaml \
  | kubectl --context "$CTX" apply -f -
