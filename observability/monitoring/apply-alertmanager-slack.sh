#!/usr/bin/env bash
# Upgrades kube-prometheus-stack with both values files (Alertmanager -> Slack, Grafana admin
# from a Secret) in ONE helm upgrade.
#
#   observability/monitoring/apply-alertmanager-slack.sh [--test]
#
# Secrets are created outside this script and are only CHECKED here (key names, never values):
#   monitoring/alertmanager-slack  key webhook_url    (created by hand; holds the Slack webhook)
#   monitoring/grafana-admin       keys admin-user, admin-password  (create-grafana-admin-secret.sh)
# With --test it fires a synthetic InsightHubSlackTest alert to prove delivery to #alerts.
set -euo pipefail
CTX="${KUBE_CONTEXT:-kind-insighthub-lab}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CHART_VERSION=91.8.1
k() { kubectl --context "$CTX" -n monitoring "$@"; }

need_keys() { # secret key...
  local secret=$1; shift
  local have key
  have=$(k get secret "$secret" -o go-template='{{range $k,$v := .data}}{{$k}} {{end}}' 2>/dev/null) \
    || { echo "missing Secret monitoring/$secret" >&2; exit 1; }
  for key in "$@"; do
    case " $have" in *" $key "*) ;; *) echo "Secret monitoring/$secret has no key $key" >&2; exit 1;; esac
  done
  echo "secret monitoring/$secret ok (keys: $have)"
}

need_keys alertmanager-slack webhook_url
"$HERE/create-grafana-admin-secret.sh" >/dev/null   # no-op when it already exists
need_keys grafana-admin admin-user admin-password

prom_before=$(k get pod prometheus-kube-prom-stack-prometheus-0 -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
helm --kube-context "$CTX" upgrade kube-prom-stack prometheus-community/kube-prometheus-stack \
  --version "$CHART_VERSION" --namespace monitoring \
  -f "$HERE/kube-prometheus-stack.values.yaml" -f "$HERE/alertmanager-slack.values.yaml" \
  --wait --timeout 10m >/dev/null
echo "helm release upgraded"
k rollout status statefulset/alertmanager-kube-prom-stack-alertmanager --timeout=180s
k rollout status deploy/kube-prom-stack-grafana --timeout=180s
prom_after=$(k get pod prometheus-kube-prom-stack-prometheus-0 -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
[ "$prom_before" = "$prom_after" ] && echo "Prometheus pod unchanged (no restart)" \
  || echo "WARNING: Prometheus pod was recreated ($prom_before -> $prom_after)"

if [ "${1:-}" = "--test" ]; then
  k exec alertmanager-kube-prom-stack-alertmanager-0 -c alertmanager -- \
    amtool alert add --alertmanager.url=http://localhost:9093 \
      alertname=InsightHubSlackTest severity=info incident=slack-test \
      --annotation=summary="Day 4 test alert - Alertmanager to Slack alerts channel" \
      --annotation=description="Synthetic alert fired by apply-alertmanager-slack script with test flag" \
      --end="$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  echo "test alert sent; expect it in #alerts within ~10-20s (group_wait 10s)"
fi
