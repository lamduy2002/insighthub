#!/usr/bin/env bash
# Keeps localhost:8000 -> svc/insighthub-api alive across pod restarts (chaos scripts
# and rollouts kill the pod a plain `kubectl port-forward` is bound to). Run detached.
CTX="${KUBE_CONTEXT:-kind-insighthub-lab}"; NS="${NAMESPACE:-insighthub-local}"
while true; do
  kubectl --context "$CTX" -n "$NS" port-forward svc/insighthub-api 8000:8000 --address 127.0.0.1 >/dev/null 2>&1
  sleep 1
done
