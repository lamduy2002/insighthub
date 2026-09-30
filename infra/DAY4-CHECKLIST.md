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
| MH3 | Grafana dashboard ≥ 9 panels | ✅ 12 panel, import vào Grafana (uid `insighthub-red`), mọi panel có data qua `/api/ds/query`. File `observability/grafana-dashboards/insighthub-red.json`. Ảnh chụp Slack/Grafana do người dùng tự chụp, không nằm trong repo |
| MH4 | Recording rules cho anomaly bands | ✅ `kubectl get prometheusrule -n monitoring insighthub-anomaly`: 17 recording rules (SLI + 3 band × avg/stddev/upper), 20/20 rule health `ok` |
| MH5 | Alert rules cho 3 anomaly (`promtool check rules`) | ✅ `promtool check rules` SUCCESS (20 rules), `promtool test rules` SUCCESS (5 case, chạy 3 lần đều exit 0). Chưa fire thật (chờ incident) |
| MH6 | Alertmanager → Slack | ✅ FIRING + RESOLVED của test alert tới `#alerts` (người dùng đã chụp ảnh), và cả 3 alert incident đều được Alertmanager gửi Slack (`alertmanager_notifications_total{integration="slack"}` = 8 sau incident 3 gồm cả thông báo resolved, `alertmanager_notifications_failed_total` = 0). Ảnh chụp: làm tay |
| MH7 | Incident #1 LLM latency spike + RCA | ✅ `InsightHubLLMLatencyAnomaly` FIRING 19:23:51Z (p95 4.86s > band 1.24s), resolved 19:32:36Z. `evidence/incident-1.json`, RCA subagent độc lập: **đúng** |
| MH8 | Incident #2 queue backlog + RCA | ✅ `InsightHubQueueDepthAnomaly` FIRING 19:46:51Z (23 > band 5), resolved ≤19:56:36Z. `evidence/incident-2.json`: **đúng** (không xác định được ai scale worker, tự ghi `unverified`) |
| MH9 | Incident #3 error burst + RCA | ✅ `InsightHubErrorRateAnomaly` FIRING 20:10:21Z (0.434 > band 0.05), resolved 20:16:23Z. `evidence/incident-3.json`: **đúng nguyên nhân gốc, sai nhẹ cơ chế** ("pod bị xoá" thay vì StatefulSet scale 0) |
| MH10 | RCA cite metric + timestamp | ✅ 43 sample (17+12+14) lấy nguyên từ `harvest-samples.py`, kiểm bằng logic `verify.py:602-633`: 43/43 khớp `query_range`; mỗi hypothesis có dạng `metric{labels} = giá trị @ timestamp` |
| MH11 | Quiz 5 câu ≥ 4/5 | ⚪ **không nộp** (quyết định của người dùng; bài nộp ghi rõ, không tự tính là đạt) |
| MH12 | MLOps overview notes 4 block | ✅ `observability/mlops-overview-notes.md` do người dùng đọc, duyệt và cung cấp nội dung cuối (bản nháp ban đầu của agent đã bị thay toàn bộ). 4 block: vòng đời ML, 4 khái niệm (Registry/Approval Gate/Drift/Rollback), artifact app khác model, ranh giới ML Engineer/DevOps. Spec không định nghĩa "4 block" nên cách chia này là cách diễn giải |

## B. Non-functional (§8.3, dòng 977-982)

| # | Yêu cầu | Trạng thái |
|---|---|---|
| 1 | Baseline ≥ 1h trước alert | ⏳ bắt đầu ~12:56 UTC (19:56 giờ máy +07); đủ từ ~13:56 UTC (20:56 +07) |
| 2 | Resource limits Prometheus pod | ✅ 200m/512Mi → 1000m/1536Mi |
| 3 | Recording rules cho expensive query | ✅ band 1h subquery được record 30s/lần |
| 4 | Retention 15 ngày | ✅ `retention: 15d` |
| 5 | AI RCA prompt "evidence-first" | ✅ `observability/rca-prompt.md`, dùng cho cả 3 RCA |

## C. Acceptance 8.5 — 12 dòng (dòng 1023-1035)

| # | Dòng | Trạng thái |
|---|---|---|
| 1 | `kubectl get servicemonitor -n insighthub` → exists | ✅ ns thực tế `insighthub-local` (kind), 3 ServiceMonitor; ghi rõ trong evidence |
| 2 | `/api/v1/targets` mọi target UP, đủ 5 thành phần | ✅ 3 target app + 15 target stack UP; worker/web gián tiếp |
| 3 | Dashboard 9+ panels, no "No data" | ✅ 12 panel, 0 panel No data (đã kiểm qua Grafana API) |
| 4 | `kubectl get prometheusrule -n monitoring -o yaml` → rules | ✅ |
| 5 | `promtool check rules anomaly-rules.yaml` → SUCCESS | ✅ (file: `observability/prometheus-rules/anomaly-rules.yaml`) |
| 6 | Test alert → Slack `#alerts` | ✅ FIRING + RESOLVED tới Slack |
| 7 | `./scripts/chaos/inject-llm-latency.sh` → alert fires in 5min | ✅ chạy thật: inject 19:20:29Z → FIRING 19:23:51Z (**3 phút 22 giây**) |
| 8-10 | `incident-1/2/3.json` có evidence + timestamp | ✅ `evidence/incident-{1,2,3}.json` (không nằm trong `rca-reports/` như spec ghi) |
| 11 | `mlops-overview-notes.md` 4 block | ✅ (`observability/mlops-overview-notes.md`) |
| 12 | Quiz: 5/5 | ⚪ không nộp (xem MH11) |

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
| 7 | Cost (**ước lượng, fixture mode**) | recording rule `insighthub:embedding_est_cost_usd:per_hour` | rules | đơn giá cố định, ghi trong rule |
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

## K. Kết quả chạy 3 incident (2026-09-29 UTC)

| # | Fault tiêm | Alert firing (từ lúc inject) | Resolved | RCA của subagent độc lập |
|---|---|---|---|---|
| 1 | sleep 4s trong `generate()` (ConfigMap sitecustomize, rollout api) | 3'22" | 19:32:36Z | đúng, kể cả cơ chế (fault tự gắn nhãn `CHAOS_*` trong pod spec) |
| 2 | worker scale 0 + 40 upload | 3'04" | ≤19:56:36Z | đúng, tự nhận không biết ai scale |
| 3 | Redis scale 0 (POST /documents → 500) | 3'04" | 20:16:23Z | đúng nguyên nhân gốc; sai nhẹ cơ chế |

- Quy trình mỗi incident: inject → alert firing (đã báo người dùng chụp Slack + Grafana) → tự revert → resolved → RCA bằng subagent mới không biết lỗi (chỉ đọc prompt + MCP + harvest script) → tôi đối chiếu rồi mới thêm `injected_fault`/`injected_fault_evaluation`; `hypotheses`, `ruled_out`, `samples` không bị sửa. Nghỉ ≥10' giữa các incident.
- **Đã sửa giữa chừng**: (1) `rca-prompt.md` quy tắc 5 mâu thuẫn với verifier (baseline phải nằm trong cửa sổ vì `samples` bắt buộc nằm trong `[started_at, ended_at]`); (2) guard baseline trong `lib.sh` lấy nhầm series đầu tiên sau khi pod api đổi (chặn incident 2 lần đầu) — giờ cộng mọi series.
- **Drift so với chart — đã xử lý ở mức code**: Deployment `insighthub-api` đang chạy với `maxSurge: 0, maxUnavailable: 1` do `kubectl patch` (node 2 CPU đã 99% CPU requests nên pod api thứ hai không schedule được khi rollout). Giờ chart có biến `api.strategy` (mặc định rỗng; `values-dev.yaml` không đổi — render dev giống hệt byte-by-byte) và `values-local.yaml` đặt đúng giá trị đó, nên `helm upgrade` sau này KHÔNG còn ghi đè. Chưa chạy `helm upgrade` (theo yêu cầu): live vẫn là bản patch tay, giống hệt về nội dung. Hệ quả vận hành: mỗi rollout api mất pod ~30 giây (available replicas = 0), có trong dữ liệu RCA #1.
- **Hạn "tươi" của RCA**: `verify.py:605-606` yêu cầu `started_at`/`ended_at` ≤24h. Incident 1 bắt đầu cửa sổ 2026-09-29T19:05:29Z nên **hết tươi lúc 2026-09-30T19:05Z (02:05 ngày 01/10 giờ máy)**. Chạy lại verify sau mốc đó sẽ INCOMPLETE dù mọi thứ vẫn đúng; output verify đã lưu trong `evidence/` là bằng chứng.

## L. Chỗ lệch so với spec (ghi để trainer và người đọc khỏi hiểu nhầm)

| Spec ghi | Thực tế | Lý do |
|---|---|---|
| `kubectl get servicemonitor -n insighthub` (§8.5) | namespace **`insighthub-local`** (kind local) | Day 4 chạy local theo Guide local/AWS (§0.2); EKS `insighthub-dev` đã xoá sau Day 3, không giữ cloud cả tuần |
| `cat rca-reports/incident-{1,2,3}.json` | **`evidence/incident-{1,2,3}.json`** | `evidence/` nằm ngoài fingerprint nguồn (`verify.py:32-34`) nên sinh RCA không làm lệch `source_sha256`; role trong `day4.json` là `rca`, `rca_2`, `rca_3` |
| Prometheus quan sát đủ 5 thành phần bằng ServiceMonitor | api, postgres, redis, web có tín hiệu trực tiếp (ServiceMonitor/Probe); **ingestion-worker quan sát gián tiếp**: cAdvisor + kube-state-metrics (pod, CPU, memory, replica, restart) + `redis_key_size{key="arq:queue"}` | Không sửa code worker (code Day 1). Spec §0.4: "5 thành phần không đồng nghĩa 5 pods hoặc 5 endpoint Prometheus". Hệ quả: không có metric nội bộ của worker (số job, thời gian xử lý) |
| Panel token và cost | **ước lượng, fixture mode**: `insighthub_embedding_estimated_tokens_total` × đơn giá cố định 0.02 USD/1M token | `RAG_MODE=fixture` nên `insighthub_llm_tokens_total` luôn = 0; không tạo series giả (§0.4). Ghi rõ trong tiêu đề panel và description dashboard |
| Incident #1 "LLM latency spike" | **độ trễ được tiêm** (sitecustomize trong ConfigMap, `sleep 4s` trong `generate()`), không phải provider chậm thật | Fixture ép cả 2 provider; đổi embedding cần reindex (§0.4). RCA ghi đúng điều này ở `injected_fault` |
| Grafana dashboard URL | dashboard chạy **local** (`http://localhost:3001/d/insighthub-red`, không truy cập được từ ngoài); bằng chứng nộp là JSON trong repo + ảnh chụp | Grafana Cloud không dùng; kind local |
| Alertmanager → Slack `#alerts` | có, nhưng webhook nằm trong Secret `monitoring/alertmanager-slack`, không trong git | Không commit secret |
| Quiz MH11 | không nộp | Quyết định của người dùng |
| `scripts/chaos/inject-llm-latency.sh` "alert fires in 5min" | firing sau **3'22"** | `for: 2m` + cửa sổ rate 5m |

## M. Trạng thái cuối
MH1-MH10 ✅, MH11 ⚪ không nộp, MH12 ✅. `scripts/verify-day-4.sh --prometheus-url http://localhost:9090` PASS (3 incident, 43 sample). Verifier chỉ kiểm phần trích dẫn số liệu; `milestone_complete` luôn `false` và phần Slack/panel/MLOps/quiz vẫn do người chấm đánh giá. Phải chạy verify khi Prometheus còn sống và RCA còn tươi (incident 1 hết tươi lúc 2026-09-30T19:05Z = 02:05 ngày 01/10 giờ máy).
