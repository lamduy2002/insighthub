# Day 4 — Submission

Ngày nộp: 30/09/2026 · Học viên: lamduy2002 (DO2603) · Branch `day4-observability` · PR: https://github.com/lamduy2002/insighthub/pull/3

---

## 1. Submission Format (§8.8)

```
Day 4 - Lam Duy

✓ ServiceMonitor: https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/observability/k8s/servicemonitor-api.yaml
   + redis/postgres exporter: https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/observability/k8s/exporters.yaml
   + web (Probe/blackbox): https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/observability/k8s/blackbox.yaml
   (namespace insighthub-local vì chạy trên kind local, không phải "insighthub")
✓ Grafana dashboard URL: chạy local, http://localhost:3001/d/insighthub-red
   (không truy cập được từ ngoài) - JSON: https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/observability/grafana-dashboards/insighthub-red.json
   12 panel, không panel nào "No data"; ảnh chụp do học viên đính kèm khi nộp.
✓ Anomaly rules: https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/observability/prometheus-rules/anomaly-rules.yaml
   unit test: https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/observability/prometheus-rules/anomaly-rules_test.yaml
   (promtool check rules + promtool test rules: exit 0)
✓ RCA reports:
  - incident-1.json (LLM latency): https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/evidence/incident-1.json
  - incident-2.json (queue backlog): https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/evidence/incident-2.json
  - incident-3.json (error burst): https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/evidence/incident-3.json
✓ MLOps overview notes: https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/observability/mlops-overview-notes.md
✓ Quiz: không nộp
```

Theo §4.1:
```
✓ Verify command output: https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/evidence/day4-verify-output.txt  (PASS day4)
   báo cáo JSON: https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/evidence/day4-verify-report.json
✓ AI prompt log: https://github.com/lamduy2002/insighthub/blob/2b8b08e7b8b2ed7e09c9104d9ea43846c5b66c13/ai-prompts/day4.md
```

---

## 2. Kết quả verifier

`scripts/verify-day-4.sh --prometheus-url http://localhost:9090` → **PASS day4** (`runtime_verified=true`, 3 incident, 43 sample khớp `query_range`).
Verifier chỉ kiểm phần trích dẫn số liệu và cấu trúc rules/dashboard (`milestone_complete` luôn `false`): Slack, độ phủ panel, MLOps và quiz do người chấm đánh giá.

## 3. Ba incident

| # | Fault tiêm | Alert firing (sau khi inject) | Resolved (UTC 29/09) | RCA subagent độc lập |
|---|---|---|---|---|
| 1 | `sleep 4s` trong `generate()` (ConfigMap sitecustomize) | 3'22" | 19:32:36 | đúng |
| 2 | ingestion-worker scale 0 + 40 upload | 3'04" | ≤19:56:36 | đúng |
| 3 | Redis scale 0 (`POST /documents` → 500) | 3'04" | 20:16:23 | đúng nguyên nhân gốc, sai nhẹ cơ chế |

Mỗi alert đã được Alertmanager gửi tới Slack `#alerts` (FIRING và RESOLVED). Cửa sổ chaos: `evidence/chaos-*-window.json`.

## 4. Chỗ lệch spec và giới hạn (trung thực)

- Namespace `insighthub-local`, RCA ở `evidence/` thay vì `rca-reports/`, Grafana chạy local (chi tiết: `infra/DAY4-CHECKLIST.md` mục L).
- **ingestion-worker quan sát gián tiếp** (cAdvisor + kube-state-metrics + `redis_key_size`), không có endpoint `/metrics`; không sửa code Day 1 (spec §0.4).
- **Incident 1 là độ trễ được tiêm**, không phải provider chậm thật (`RAG_MODE=fixture`); panel token và cost là **ước lượng, fixture mode**.
- Quiz MH11 không nộp.
- PR #3 xếp chồng lên PR #2 (Day 3) — diff vào `main` gồm cả Day 3 cho tới khi #2 merge.
- Verify phải chạy khi Prometheus còn sống; RCA hết "tươi" (≤24h) lúc 2026-09-30T19:05Z (incident 1). Output PASS ở trên là bằng chứng nếu chạy lại sau mốc đó.

## 5. Hướng dẫn tái lập (từ code và dữ liệu mẫu)

```bash
# 0. kind insighthub-lab + 2 chart Day 3 (xem infra/DAY3-CHECKLIST.md), cài promtool
# 1. Stack (Secret Grafana phải có trước)
observability/monitoring/create-grafana-admin-secret.sh
helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack --version 91.8.1 \
  -n monitoring --create-namespace -f observability/monitoring/kube-prometheus-stack.values.yaml
# 2. Scrape, rules, quyền MCP read-only, dashboard
kubectl apply -f observability/k8s/servicemonitor-api.yaml -f observability/k8s/exporters.yaml \
  -f observability/k8s/blackbox.yaml -f observability/k8s/prometheusrule-insighthub.yaml \
  -f observability/k8s/mcp-readonly-rbac.yaml
observability/grafana-dashboards/apply.sh
# 3. Slack: tự tạo Secret monitoring/alertmanager-slack (key webhook_url), rồi
observability/monitoring/apply-alertmanager-slack.sh --test
# 4. Baseline >=1h (sinh tải nhẹ), rồi từng incident (script có guard baseline và tự revert)
kubectl -n monitoring port-forward svc/kube-prom-stack-prometheus 9090:9090 &
scripts/chaos/inject-llm-latency.sh; scripts/chaos/inject-queue-backlog.sh; scripts/chaos/inject-error-burst.sh
# 5. RCA theo observability/rca-prompt.md, samples bằng scripts/chaos/harvest-samples.py, rồi
python3 evidence/make-day4-json.py
scripts/verify-day-4.sh --prometheus-url http://localhost:9090
```
