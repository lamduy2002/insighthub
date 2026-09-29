#!/usr/bin/env bash
# Provisions the dashboards in this folder through the Grafana sidecar (ConfigMap with label
# grafana_dashboard=1). Grafana runs without persistence, so a dashboard imported through the
# UI/API is lost on every pod restart; a labelled ConfigMap is re-loaded automatically.
set -euo pipefail
CTX="${KUBE_CONTEXT:-kind-insighthub-lab}"
HERE="$(cd "$(dirname "$0")" && pwd)"
kubectl --context "$CTX" -n monitoring create configmap insighthub-dashboards \
  --from-file="$HERE/insighthub-red.json" --dry-run=client -o yaml \
  | kubectl --context "$CTX" label --local -f - grafana_dashboard=1 -o yaml \
  | kubectl --context "$CTX" apply -f -
