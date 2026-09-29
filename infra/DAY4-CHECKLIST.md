# Day 4 Checklist — InsightHub (DO2603)

Checklist duy nhất cho Day 4 (AIOps + MLOps Overview). Mọi dòng ghi nguồn và trạng thái. Khẳng định về verifier trích dòng `scripts/verify.py`.

## Nguồn đã đọc
Spec §0, §2.3, §2.5, §4, §8 · `docs/Guide_Local_AWS_Cost_DO2603.md` · `docs/lab-guides/Day4-AIOps-Observability.md` · `scripts/VERIFICATION_CONTRACT.md` · `scripts/verify.py` (`day4` 638-662, `verify_rca_component` 593-635, `validate_rule_tests` 563-590, `artifact` 321-332, `evidence` 310-318) · `api/app/core/metrics.py` · `ingestion-worker/` · `tests/milestones/` (không có day4, và không cần).

## Quyết định phạm vi (chốt 2026-09-29)
1. **Token/cost**: dùng `insighthub_embedding_estimated_tokens_total`; cost = tokens × đơn giá cố định qua recording rule. Tiêu đề panel + description dashboard ghi rõ "ước lượng, fixture mode". Không dùng provider thật, không Ollama.
2. **Worker**: KHÔNG sửa code worker (code Day 1). Quan sát gián tiếp: redis_exporter (queue depth thật) + cAdvisor/kube-state-metrics cho pod worker. Viện dẫn spec §0.4: "5 thành phần không đồng nghĩa 5 pods hoặc 5 endpoint Prometheus".
3. **Cách chấm chưa xác nhận**: tự chạy `verify-day-4.sh`, lưu output vào `evidence/`, kèm hướng dẫn tái lập trong submission (như Day 3).
4. Chỉ MH1-MH12. Bỏ Should/Nice-have. blackbox-exporter cho web: làm cuối, chỉ nếu còn giờ.

## A. Must-have MH1–MH12 (§8.4, dòng 993-1006)

| # | Yêu cầu | Trạng thái |
|---|---|---|
| MH1 | ServiceMonitor applied | ✅ 3 ServiceMonitor ns `insighthub-local`: `insighthub-api`, `insighthub-redis`, `insighthub-postgres` (`observability/k8s/`) |
| MH2 | Prometheus quan sát đủ 5 thành phần | ✅ api (`up`=1), postgres (`pg_up`=1), redis (`redis_up`=1, `redis_key_size{arq:queue}`) trực tiếp; web trực tiếp qua blackbox-exporter (`probe_success{job="insighthub-web-probe"}`=1, `Probe` CRD), worker gián tiếp qua cAdvisor + kube-state-metrics (spec §0.4) |
| MH3 | Grafana dashboard ≥ 9 panels | ✅ 12 panel, import vào Grafana (uid `insighthub-red`), mọi panel có data qua `/api/ds/query`. File `observability/grafana-dashboards/insighthub-red.json`. Còn thiếu: ảnh chụp màn hình (làm tay) |
| MH4 | Recording rules cho anomaly bands | ✅ `kubectl get prometheusrule -n monitoring insighthub-anomaly`: 17 recording rules (SLI + 3 band × avg/stddev/upper), 20/20 rule health `ok` |
| MH5 | Alert rules cho 3 anomaly (`promtool check rules`) | ✅ `promtool check rules` SUCCESS (20 rules), `promtool test rules` SUCCESS (5 case, chạy 3 lần đều exit 0). Chưa fire thật (chờ incident) |
| MH6 | Alertmanager → Slack | 🔸 cấu hình sẵn + validate (`amtool check-config` SUCCESS, routing test đúng), **chưa apply**: `observability/monitoring/apply-alertmanager-slack.sh`. **CẦN USER**: webhook |
| MH7 | Incident #1 LLM latency spike + RCA | ❌ (sau baseline ≥1h) |
| MH8 | Incident #2 queue backlog + RCA | ❌ |
| MH9 | Incident #3 error burst + RCA | ❌ |
| MH10 | RCA cite metric + timestamp | ❌ |
| MH11 | Quiz 5 câu ≥ 4/5 | ❌ **CẦN USER** |
| MH12 | MLOps overview notes 4 block | 🔸 nháp `observability/mlops-overview-notes.md` (người học phải đọc và viết lại bằng lời mình; spec không định nghĩa "4 block", cách chia ghi ở đầu file) |

## B. Non-functional (§8.3, dòng 977-982)

| # | Yêu cầu | Trạng thái |
|---|---|---|
| 1 | Baseline ≥ 1h trước alert | ⏳ bắt đầu ~12:56 UTC (19:56 giờ máy +07); đủ từ ~13:56 UTC (20:56 +07) |
| 2 | Resource limits Prometheus pod | ✅ 200m/512Mi → 1000m/1536Mi |
| 3 | Recording rules cho expensive query | ✅ band 1h subquery được record 30s/lần |
| 4 | Retention 15 ngày | ✅ `retention: 15d` |
| 5 | AI RCA prompt "evidence-first" | ❌ |

## C. Acceptance 8.5 — 12 dòng (dòng 1023-1035)

| # | Dòng | Trạng thái |
|---|---|---|
| 1 | `kubectl get servicemonitor -n insighthub` → exists | ✅ ns thực tế `insighthub-local` (kind), 3 ServiceMonitor; ghi rõ trong evidence |
| 2 | `/api/v1/targets` mọi target UP, đủ 5 thành phần | ✅ 3 target app + 15 target stack UP; worker/web gián tiếp |
| 3 | Dashboard 9+ panels, no "No data" | ✅ 12 panel, 0 panel No data (đã kiểm qua Grafana API) |
| 4 | `kubectl get prometheusrule -n monitoring -o yaml` → rules | ✅ |
| 5 | `promtool check rules anomaly-rules.yaml` → SUCCESS | ✅ (file: `observability/prometheus-rules/anomaly-rules.yaml`) |
| 6 | Test alert → Slack `#alerts` | ❌ cần webhook |
| 7 | `./scripts/chaos/inject-llm-latency.sh` → alert fires in 5min | 🔸 script có (chưa chạy thật: guard baseline ≥1h chặn); kỳ vọng alert nổ ~3' sau inject (`for: 2m`) |
| 8-10 | `incident-1/2/3.json` có evidence + timestamp | ❌ |
| 11 | `mlops-overview-notes.md` 4 block | ❌ |
| 12 | Quiz 5/5 | ❌ cần user |

## D. Verifier Day 4 — sự thật từ code

- **Không có REQUIRED_TESTS day 4** (`verify.py:36-42` chỉ có 1,3,5,6); `day4()` không gọi `run_tests` ⇒ không cần `tests/milestones/day4/`.
- **7 artifact role** trong `evidence/day4.json` (`{path, sha256}`): `dashboard` (JSON) · `rules` (YAML) · `rule_tests` (YAML, cùng thư mục với rules) · `rca`/`rca_2`/`rca_3` (JSON) · `mlops_notes` (md).
- Dashboard: ≥9 panel có `targets[].expr` thật, đếm đệ quy qua `panels[].panels[]` (640-650); row không tính.
- `rule_tests.rule_files[]` resolve theo `tests.parent` phải == file `rules` (`validate_rule_tests`).
- promtool: `promtool check rules <rules>` + `promtool test rules <tests>` (611-613).
- Prometheus: `GET /api/v1/query_range?start=at&end=at+1&step=1` (623-624); khớp `|ts-at|<1s` và `rel_tol=1e-6` (631). **Harvest sample bằng đúng query_range**, không gõ tay.
- `--prometheus-url` bắt buộc (610); **Prometheus phải sống lúc verify** (`http()` ném Incomplete nếu không kết nối).
- RCA: `started_at`/`ended_at` **tươi ≤ 24h** (605-606); sample nằm trong cửa sổ; labels value là string.
- `mode` phải `real` (`main()`); `source_sha256` == fingerprint ⇒ **tạo `evidence/day4.json` là bước CUỐI**.

## E. 9 panel ↔ metric

| # | Panel | Biểu thức | Nguồn | Ghi chú |
|---|---|---|---|---|
| 1 | Rate | `sum(rate(insighthub_http_requests_total[5m]))` | api | ✅ |
| 2 | Errors | `sum(rate(insighthub_http_requests_total{status=~"5.."}[5m]))`, `rate(insighthub_ingestion_errors_total[5m])` | api | ✅ |
| 3 | Duration | `histogram_quantile(0.95, …insighthub_rag_query_latency_seconds_bucket)` | api | ✅ |
| 4 | Queue depth | `redis_key_size{key=~"arq:queue.*"}` / list length | redis_exporter | cần `--check-keys` |
| 5 | Token usage (**ước lượng, fixture mode**) | `sum(rate(insighthub_embedding_estimated_tokens_total[5m]))` | api | LLM tokens thật = 0 ở fixture |
| 6 | Latency p95 (LLM) | `histogram_quantile(0.95, …insighthub_llm_call_latency_seconds_bucket)` | api | ✅ |
| 7 | Cost (**ước lượng, fixture mode**) | recording rule `insighthub:embedding_cost_usd:rate5m` | rules | đơn giá cố định, ghi trong rule |
| 8 | Pod resources | `container_memory_working_set_bytes`, `container_cpu_usage_seconds_total` (ns insighthub-local) | cAdvisor | gồm pod worker |
| 9 | Deploy annotations | `kube_deployment_status_observed_generation`, `kube_pod_start_time` | KSM | + Grafana annotation |

## F. 3 incident và cách inject (scripts/chaos/, đều có `--revert`)

| # | Incident | Inject | Tín hiệu anomaly |
|---|---|---|---|
| 1 | LLM latency spike | `inject-llm-latency.sh` | p95 `insighthub_llm_call_latency_seconds` vọt |
| 2 | Queue backlog | `inject-queue-backlog.sh`: scale worker=0 + upload burst | queue depth + `documents_total{status="pending"}` |
| 3 | Error burst | `inject-error-burst.sh` | `rate(insighthub_http_requests_total{status=~"5.."})` / `ingestion_errors_total` |

Mỗi incident: baseline → failure → recovery, RCA JSON `{incident_id, started_at, ended_at, hypotheses[], samples[{metric,labels,timestamp,value}]}`.
Lưu ý: cluster chạy `LLM_PROVIDER=fixture` nên `llm_call_latency` không có độ trễ mạng thật; cách inject #1 phải thiết kế để tạo latency thật mà không sửa code (xác định ở bước script).

## G. Việc CẦN USER làm tay
1. **Slack workspace + Incoming Webhook `#alerts`** (MH6). Webhook vào K8s Secret, không commit.
2. **Quiz 5 câu** (MH11).
3. Xác nhận cách trainer chấm (Prometheus có sống lúc chấm không).

## H. Ước lượng thời gian
promtool 5' · exporter+SM 30' · chaos scripts 40' · rules+unit tests 60' · dashboard 60' · Slack/Alertmanager 20' · chạy 3 incident + RCA 75' · MLOps notes 30' · evidence+verify 40' · prompt log/PR 25'. **Tổng ~6.5h** (+ baseline 1h chạy song song).

## I. Rủi ro
| Rủi ro | Mức | Chi tiết |
|---|---|---|
| Baseline ≥1h | ⏳ | Không rút ngắn (pitfall §8.7). Không bắn alert trước mốc. |
| RCA tươi ≤24h | 🔴 | Chạy 3 incident sát giờ nộp; sẵn sàng chạy lại. |
| Prometheus phải sống lúc chấm | 🔴 | Cách chấm chưa xác nhận. Giảm nhẹ: lưu output verify vào `evidence/`, hướng dẫn tái lập trong submission. |
| Thiếu Slack | 🟡 | MH6 + acceptance #6 không hoàn thành; verifier không kiểm Slack nhưng rubric L3 cần alert fire thật. |
| Token/cost là ước lượng | 🟡 | Ghi rõ trong tiêu đề panel; không tạo series giả (§0.4). |
| Worker quan sát gián tiếp | 🟡 | Không có metric nội bộ worker; MH2 dựa §0.4. |
| RAM host 5.8Gi | 🟡 | Còn ~2.6Gi; exporter đặt limit nhỏ. |
| fingerprint | 🟡 | `observability/`, `scripts/`, `infra/` vào `source_sha256`; `day4.json` tạo cuối. |
| promtool | 🟢 | ✅ đã cài 3.15.0 (`~/.local/bin`), sha256 khớp. |

## J. Ghi chú thiết kế và rủi ro phát sinh khi làm (2026-09-29)

- **Mốc baseline (UTC)**: Prometheus scrape api từ ~12:56; redis/postgres exporter từ ~13:06. Alert có guard trong rule (`count_over_time(up{job="insighthub-api"}[3h]) >= 115` ≈ 1h) và mỗi script chaos tự từ chối chạy khi chưa đủ (`--skip-baseline-check` để bỏ qua có chủ đích). **Incident #2 (queue) nên chạy sau ~14:10 UTC** để band queue đủ 1h dữ liệu redis.
- **Band = avg_1h + max(3σ, floor)**, cửa sổ lùi 10' (`offset 10m`). Lý do: unit test cho thấy nếu không lùi, sự cố 7' làm avg+3σ vượt luôn mức bất thường ⇒ alert không nổ. Sàn (floor): latency 1s, queue 5 job, error 5% — vì baseline gần phẳng (σ≈0).
- **Incident #1 là fault injection, không phải LLM chậm thật**: `RAG_MODE=fixture` ép cả 2 provider = fixture (`api/app/core/config.py:71-77`), đổi embedding cần reindex (§0.4), nên không dùng stub provider. Script mount `sitecustomize.py` (ConfigMap) bọc `app.services.llm.generate` bằng `sleep`. RCA phải ghi đúng: độ trễ được tiêm, không phải provider. Hook đã test offline (0.00s → 1.50s); **chưa test trên pod thật** (sẽ làm bẩn baseline).
- **Incident #3** = Redis xuống (StatefulSet → 0): `/readyz` chỉ kiểm DB nên API vẫn nhận traffic, `POST /documents` không enqueue được ⇒ 5xx. Redis là emptyDir nên mất hàng chờ tạm; script xóa tài liệu `chaos-*` khi revert. **Chưa xác nhận trên cluster** rằng arq trả 5xx (thay vì treo) — kiểm khi chạy thật.
- **Port-forward**: `scripts/chaos/api-forward.sh` tự nối lại; cần chạy nền cho load baseline và chaos #1 (restart pod api).
- `evidence/chaos-*-window.json` ghi cửa sổ started_at / fault_removed_at / ended_at để viết RCA.
- Test alert dùng `$value` trong annotation ⇒ đặt alert cùng group với recording rule (khác group thì giá trị dao động 39↔42 giữa các lần chạy vì group chạy song song).
- **Label route**: label `endpoint` của app bị trùng với `endpoint="http"` của ServiceMonitor nên Prometheus đổi thành **`exported_endpoint`** (`/chat`, `/documents`, ...). Dùng `exported_endpoint` trong query/RCA/harvest. Đã sửa panel 1 và unit test.
- **MCP cho RCA (§8.1)**: `~/.kube/insighthub-mcp-readonly.kubeconfig` trước đó trỏ minikube đã chết (127.0.0.1:32771). Đã tạo lại cho kind: ServiceAccount `mcp-readonly` (Role chỉ ns `insighthub-local`, không secrets, không write; token 72h, hết hạn ~2026-10-02 — tạo lại bằng `kubectl -n insighthub-local create token mcp-readonly --duration=72h`). Bản cũ lưu ở `~/.kube/insighthub-mcp-readonly.kubeconfig.minikube.bak`. Kiểm bằng gọi thật: Prometheus MCP trả `insighthub_http_requests_total`, Kubernetes MCP liệt kê pod ns `insighthub-local`; `auth can-i` xác nhận delete/create/patch/secrets đều `no`.
- **Alertmanager → Slack**: webhook đọc từ Secret `monitoring/alertmanager-slack` qua `slack_api_url_file`, không nằm trong git. Chỉ alert `InsightHub*` đi Slack; alert mặc định của stack vào receiver `null`.
- **Tiện ích**: `scripts/chaos/harvest-samples.py` lấy sample nguyên từ Prometheus (đã đối chiếu với đúng logic `verify.py:615-633`: 4/4 chấp nhận); `observability/rca-prompt.md` là prompt evidence-first.
- **Credential Grafana**: mật khẩu cũ `insighthub` đã lỡ commit (còn trong lịch sử git, bản public) nên đã **thay**: Secret `monitoring/grafana-admin` với mật khẩu ngẫu nhiên (`create-grafana-admin-secret.sh`), values dùng `grafana.admin.existingSecret`, đã xác nhận mật khẩu cũ trả 401. Lấy mật khẩu mới: `kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d`. Quét toàn bộ lịch sử git không thấy AWS key/token/private key/webhook nào; còn lại là mật khẩu Postgres lab `insighthub` ở `docker-compose.yml` và `infra/helm/insighthub-local-deps/values.yaml` (chỉ local, chưa đổi vì cần redeploy DB).
- **Grafana không có persistence**: dashboard nạp qua ConfigMap sidecar (`observability/grafana-dashboards/apply.sh`), không import tay qua API (mất khi pod restart). Strategy `Recreate` vì node kind 2 CPU không đủ chỗ cho pod Grafana thứ hai khi rolling update.
