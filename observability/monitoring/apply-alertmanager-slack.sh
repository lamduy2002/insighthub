#!/usr/bin/env bash
# Applies Alertmanager -> Slack. NOT run yet: needs the Slack incoming-webhook URL.
#
#   read -rs SLACK_WEBHOOK_URL; export SLACK_WEBHOOK_URL      # silent prompt, nothing echoed
#   observability/monitoring/apply-alertmanager-slack.sh [--test]
#
# Creates/updates Secret monitoring/alertmanager-slack from the env var (never printed, never
# written to disk), upgrades the pinned chart with both values files, waits for Alertmanager,
# and with --test fires a synthetic InsightHubSlackTest alert to prove delivery to #alerts.
set -euo pipefail
CTX="${KUBE_CONTEXT:-kind-insighthub-lab}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CHART_VERSION=91.8.1

[ -n "${SLACK_WEBHOOK_URL:-}" ] || { echo "SLACK_WEBHOOK_URL is not set" >&2; exit 1; }
case "$SLACK_WEBHOOK_URL" in https://hooks.slack.com/services/*) ;; *)
  echo "SLACK_WEBHOOK_URL does not look like a Slack incoming webhook" >&2; exit 1;; esac

# The Secret must exist before the pod that mounts it is (re)created.
printf '%s' "$SLACK_WEBHOOK_URL" \
  | kubectl --context "$CTX" -n monitoring create secret generic alertmanager-slack \
      --from-file=webhook_url=/dev/stdin --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f - >/dev/null
echo "secret monitoring/alertmanager-slack applied"

helm --kube-context "$CTX" upgrade kube-prom-stack prometheus-community/kube-prometheus-stack \
  --version "$CHART_VERSION" --namespace monitoring \
  -f "$HERE/kube-prometheus-stack.values.yaml" -f "$HERE/alertmanager-slack.values.yaml" \
  --wait --timeout 10m >/dev/null
echo "helm release upgraded"
kubectl --context "$CTX" -n monitoring rollout status statefulset/alertmanager-kube-prom-stack-alertmanager --timeout=180s

if [ "${1:-}" = "--test" ]; then
  kubectl --context "$CTX" -n monitoring exec alertmanager-kube-prom-stack-alertmanager-0 -c alertmanager -- \
    amtool alert add --alertmanager.url=http://localhost:9093 \
      alertname=InsightHubSlackTest severity=info incident=slack-test \
      --annotation=summary="Day 4 test alert: Alertmanager -> Slack #alerts" \
      --annotation=description="Synthetic alert fired by apply-alertmanager-slack.sh --test" \
      --end="$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  echo "test alert sent; expect it in #alerts within ~10-20s (group_wait 10s)"
fi
