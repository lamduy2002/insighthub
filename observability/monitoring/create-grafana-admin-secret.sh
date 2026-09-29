#!/usr/bin/env bash
# Creates Secret monitoring/grafana-admin (keys admin-user, admin-password) with a random
# password if it does not exist yet. Idempotent and silent: the password is never printed,
# echoed or written to disk. Read it later with:
#   kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
set -euo pipefail
CTX="${KUBE_CONTEXT:-kind-insighthub-lab}"
k() { kubectl --context "$CTX" -n monitoring "$@"; }

if k get secret grafana-admin >/dev/null 2>&1; then
  echo "secret monitoring/grafana-admin already exists; left unchanged"
  exit 0
fi
k get namespace >/dev/null 2>&1 || kubectl --context "$CTX" create namespace monitoring >/dev/null
# 32 random bytes -> 43 url-safe chars; piped straight into the Secret.
openssl rand -base64 32 | tr -d '\n=' | tr '+/' '-_' \
  | k create secret generic grafana-admin \
      --from-literal=admin-user=admin --from-file=admin-password=/dev/stdin >/dev/null
echo "secret monitoring/grafana-admin created (random password, not shown)"
