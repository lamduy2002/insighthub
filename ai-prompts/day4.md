# Day 4 AI Prompts

Năm prompt dưới đây là **nguyên văn** những gì tôi đã gửi trong phiên làm Day 4
(29-30/09/2026). Chép trực tiếp từ transcript của phiên (chỉ bỏ thẻ bao `<pasted_content>`
của giao diện), không chỉnh cho đẹp, không chép từ prompt pack của giảng viên. Model, phiên bản
và giờ lấy từ chính bản ghi của phiên, không nhớ lại.

---

## Prompt 1 - Dựng stack quan sát trước, khảo sát verifier song song, trình bày checklist rồi mới ghi file

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.284, Opus 5 (`claude-opus-5`), Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `Running-Project-Specification-Student.md` §0, 2.3, 2.5, 4, 8; `scripts/verify.py` (day4 638-662, verify_rca_component 593-635, validate_rule_tests 563-590); `api/app/core/metrics.py`; `ingestion-worker/`; `observability/README.md`; `docs/lab-guides/Day4-AIOps-Observability.md`. Kết quả: `observability/monitoring/kube-prometheus-stack.values.yaml`, `observability/k8s/servicemonitor-api.yaml`, bản nháp checklist trình trong chat.
**Time**: 29/09/2026, 19:49 (+07)

**Prompt**:
````
Bắt đầu Day 4 (mục 8 spec: AIOps + MLOps Overview). Hạn nộp: hết ngày mai, nên làm gọn, không mở rộng ngoài Must-have MH1-MH12.

Làm SONG SONG 2 việc:

=== VIỆC A (chạy trước, để baseline tích lũy) ===
Dựng stack quan sát trên kind insighthub-lab (cluster đã có từ Day 3, kiểm còn sống không; chết thì tạo lại và deploy lại 2 chart theo DAY3-CHECKLIST):
- Cài kube-prometheus-stack bằng Helm, pin version, namespace monitoring. Retention 15 ngày, đặt resource limits cho Prometheus pod (NFR 8.3 #2, #4).
- Cấu hình để Prometheus scrape được app: kiểm api/app/core/metrics.py xem có sẵn metric gì, và worker có metrics endpoint không.
- Chạy sinh tải nhẹ liên tục (upload + chat định kỳ) để có dữ liệu baseline thật, không phải đường thẳng 0.
- Mục tiêu: stack chạy ổn định và BẮT ĐẦU TÍCH BASELINE ngay, vì NFR 8.3 #1 đòi baseline ≥1h trước khi bắn alert.
Báo tôi khi Prometheus đã UP và có dữ liệu.

=== VIỆC B (làm trong lúc baseline chạy) ===
Khảo sát và lập infra/DAY4-CHECKLIST.md (chỉ đọc + viết 1 file, KHÔNG code gì khác).

Đọc: Running-Project-Specification-Student.md mục 0, 2.3, 2.5, 4, 8 (toàn bộ); docs/Guide_Local_AWS_Cost_DO2603.md; docs/lab-guides/ (tìm file Day 4 nếu có); scripts/VERIFICATION_CONTRACT.md; scripts/verify.py phần day4 và scripts/verify-day-4.sh; api/app/core/metrics.py; ingestion-worker/; observability/ (nếu có); tests/milestones/ (xem có day4 không).

Từ CODE verifier, trả lời chính xác (trích dòng code):
1. verify.py day4 kiểm đúng những gì? Liệt kê từng assertion.
2. Tên 7 artifact role trong evidence/day4.json (rca, rca_2, rca_3, rules, rule_tests, dashboard, mlops_notes) — mỗi cái trỏ tới file gì, format ra sao?
3. REQUIRED_TESTS cho day 4 có không? Nếu có thì tên test nào, đặt ở đâu?
4. Verifier truy vấn Prometheus thế nào để đối chiếu sample? Query range hay instant? Sai số thời gian cho phép bao nhiêu?
5. Dashboard JSON: verifier đếm panel kiểu gì, yêu cầu targets[].expr ra sao?
6. rules + rule_tests: promtool chạy lệnh gì, file test phải tham chiếu file rule như thế nào?
7. Có cần --prometheus-url không, và Prometheus phải sống lúc chạy verify đúng không?

Từ CODE app:
8. metrics.py đang expose metric nào (tên đầy đủ, loại, label)? Đủ cho 9 panel chưa (rate/errors/duration/queue depth/token usage/latency p95/cost/pod resources/deploy annotations)? Cái nào THIẾU và phải thêm?
9. Worker có expose /metrics không? Nếu không thì MH2 "đủ 5 thành phần" xử lý thế nào (exporter? postgres/redis exporter?)?
10. Có sẵn scripts/chaos/ chưa? Acceptance nhắc inject-llm-latency.sh.

Checklist phải có: MH1-MH12 + 12 dòng Acceptance 8.5 + NFR 8.3, mỗi dòng ghi nguồn và trạng thái; danh sách 9 panel và metric tương ứng; 3 incident (LLM latency spike, queue backlog, error burst) và cách inject; những thứ CẦN TÔI LÀM TAY (Slack workspace + webhook cho MH6, quiz MH11); và ước lượng thời gian từng phần.

Ghi rõ mọi rủi ro: cái gì cần chạy lâu (baseline), cái gì cần Prometheus còn sống lúc chấm, cái gì không làm được nếu thiếu Slack.

Trình bày checklist cho tôi duyệt TRƯỚC KHI ghi file. Không code gì ở lượt này.
````

**Why it worked**:
- Tách **Việc A** (cài Prometheus và chạy tải ngay) khỏi **Việc B** (chỉ đọc). Đồng hồ baseline ≥1h bắt đầu chạy trong lúc agent còn đang khảo sát: `up{job="insighthub-api"}` có dữ liệu từ ~12:56 UTC, sớm hơn khoảng 9 phút so với lúc tôi gửi prompt tiếp theo.
- 10 câu hỏi bắt buộc **trích dòng code** thay vì tóm tắt. Nhờ đó có các sự thật kiểm chứng được: Day 4 không có `REQUIRED_TESTS` (khỏi tạo `tests/milestones/day4/`), RCA phải tươi ≤24h (`verify.py:605-606`), sai số khớp mẫu là <1 giây (`verify.py:631`), `promtool` chưa cài.
- "Trình bày checklist cho tôi duyệt TRƯỚC KHI ghi file. Không code gì ở lượt này" tạo gate review. Bản nháp bộc lộ 3 quyết định thiết kế thuộc về tôi: panel token/cost khi chạy fixture (`llm_tokens_total` luôn = 0), worker không có `/metrics`, và cách trainer chấm (Prometheus có sống lúc verify không).

**What I changed**:
- Duyệt bản nháp, tự quyết 3 điểm trên và cắt phạm vi ở prompt 2 (không sửa checklist trực tiếp).
- Việc A agent tự làm ngay: values pin chart 91.8.1, tắt 4 scrape job không thể UP trên kind, ServiceMonitor cho api, script sinh tải.

---

## Prompt 2 - Chốt 3 quyết định thiết kế, cắt phạm vi, giao 5 bước theo thứ tự có mốc báo cáo

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.284, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `infra/DAY4-CHECKLIST.md`, `observability/prometheus-rules/anomaly-rules.yaml` + `anomaly-rules_test.yaml`, `observability/k8s/exporters.yaml`, `scripts/chaos/*.sh`, `observability/grafana-dashboards/insighthub-red.json`; log `promtool check/test rules` exit 0 (chạy 3 lần).
**Time**: 29/09/2026, 20:05 (+07)

**Prompt**:
````
Trả lời 3 câu:
1. Token/cost: chọn (b) — dùng insighthub_embedding_estimated_tokens_total cho panel token, cost = tokens × đơn giá cố định qua recording rule, ghi RÕ trong tiêu đề panel và dashboard description là "ước lượng, fixture mode". Không làm (a), không Ollama.
2. Worker metrics: KHÔNG sửa code worker (code Day 1, rủi ro). Thay bằng redis_exporter (queue depth thật từ ARQ list) + cAdvisor/kube-state-metrics cho pod worker. Ghi rõ trong checklist: worker quan sát gián tiếp, viện dẫn spec §0.4 "5 thành phần không đồng nghĩa 5 endpoint Prometheus".
3. Cách chấm: chưa xác nhận được. Làm như Day 3 — tự chạy verify-day-4.sh, lưu output vào evidence/, kèm hướng dẫn tái lập trong submission. Ghi rủi ro này vào checklist.

CẮT PHẠM VI (hạn nộp hết ngày mai, còn cả Day 5/6/7):
- Bỏ worker /metrics.
- blackbox-exporter cho web: để cuối, chỉ làm nếu còn giờ.
- Chỉ làm Must-have MH1-MH12, bỏ toàn bộ Should/Nice-have.

Ghi infra/DAY4-CHECKLIST.md theo bản nháp đã trình + 3 quyết định trên, rồi LÀM LUÔN theo thứ tự này, không dừng hỏi trừ khi có rủi ro mất dữ liệu:
1. Cài promtool (5')
2. postgres_exporter + redis_exporter + ServiceMonitor, nhớ label khớp NetworkPolicy (30')
3. 3 script chaos trong scripts/chaos/ (có --revert) (40')
4. Recording rules + 3 anomaly rules + promtool unit tests, chạy promtool check/test rules exit 0 (60')
5. Dashboard 9 panel JSON, import vào Grafana, xác nhận không panel nào "No data" (60')
Báo tôi sau mỗi bước bằng 3-5 dòng. Sau bước 5 dừng lại, lúc đó baseline đã đủ 1h và tôi sẽ đưa Slack webhook để làm MH6 rồi chạy 3 incident.
````

**Why it worked**:
- Mỗi quyết định có **lý do một dòng** ("code Day 1, rủi ro", "viện dẫn spec §0.4") nên agent không hỏi lại mà ghi thẳng vào checklist.
- Danh sách 5 bước có **ước lượng thời gian và tiêu chí xong** ("promtool check/test exit 0", "xác nhận không panel nào No data"). Agent kiểm đúng các tiêu chí đó: query từng target qua API của Grafana thay vì tin vào lần import thành công.
- "Dừng lại sau bước 5" giữ baseline sạch: không có incident nào chạy trước khi đủ 1h.
- Trong lúc làm, agent tự phát hiện và sửa các lỗi thật thay vì báo xanh: sai checksum promtool, `RAG_MODE=fixture` ép cả hai provider nên không thể dùng stub LLM (phải tiêm độ trễ bằng sitecustomize), band bị chính incident làm nhiễm (thêm `offset 10m`), giá trị alert dao động do 2 group chạy song song (gộp thành một group).

**What I changed**:
- Phạm vi đã cắt ngay trong prompt: bỏ worker `/metrics`, blackbox để cuối, chỉ MH1-MH12.
- Không đổi hướng tiêm incident #1 sau khi agent báo lý do dùng sitecustomize (prompt sau không nhắc lại).

---

## Prompt 3 - 7 việc không đụng baseline trong lúc chờ đủ 1h

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.284, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: Commit `e36c638`, `ee6d5cc`; `observability/k8s/blackbox.yaml`, `observability/k8s/mcp-readonly-rbac.yaml`, `scripts/chaos/harvest-samples.py`, `observability/rca-prompt.md`, `observability/monitoring/alertmanager-slack.values.yaml`, `observability/mlops-overview-notes.md` (bản nháp).
**Time**: 29/09/2026, 20:40 (+07)

**Prompt**:
````
Trong lúc chờ baseline (incident 1 sau 20:56, incident 2/3 sau ~21:10 giờ máy), làm các việc KHÔNG đụng baseline:

1. Commit WIP toàn bộ phần đã làm (observability/, scripts/chaos/, infra/DAY4-CHECKLIST.md) trên branch day4-observability (tạo từ day3-terraform nếu chưa có). Push.
2. blackbox-exporter probe http://insighthub-web:3000/api/health (+ ServiceMonitor/Probe), để web có tín hiệu trực tiếp probe_success/probe_duration_seconds (MH2). Nhớ label NetworkPolicy nếu cần. Thêm 1 panel vào dashboard nếu còn gọn.
3. Kiểm MCP cho AI RCA (§8.1): Prometheus MCP trỏ đúng http://localhost:9090 và query được insighthub_*; Kubernetes MCP trỏ cluster kind-insighthub-lab (read-only, namespace insighthub-local). Cuối Day 3 kubeconfig MCP đã đổi sang ~/.kube/insighthub-mcp-readonly.kubeconfig — kiểm nó đang trỏ đâu, sửa về kind nếu sai (vẫn read-only). Báo tôi nếu cần restart Claude Code để nạp lại MCP.
4. Viết script scripts/chaos/harvest-samples.py: nhận metric + labels + [start, end], gọi đúng /api/v1/query_range như verify.py:622-633, in ra samples {metric, labels, timestamp RFC3339, value} lấy NGUYÊN từ Prometheus — để RCA không bao giờ gõ tay số liệu.
5. Viết prompt RCA "evidence-first" (NFR 8.3 #5) vào observability/rca-prompt.md: buộc AI chỉ kết luận từ metric đã query qua MCP, mỗi hypothesis phải cite metric + timestamp, cấm suy đoán không có bằng chứng.
6. Chuẩn bị sẵn cấu hình Alertmanager → Slack #alerts, đọc webhook từ K8s Secret (KHÔNG commit webhook). Chưa apply cho tới khi tôi đưa webhook.
7. Nháp observability/mlops-overview-notes.md 4 block theo §8.3 Learning 5-7 (ML lifecycle map; Registry, Approval Gate, Drift, Rollback; ownership DevOps vs ML Engineer). Tôi sẽ đọc và sửa lại bằng lời của mình.

Báo ngắn sau mỗi mục. 20:56 dừng lại báo tôi để chạy incident 1.
````

**Why it worked**:
- Mỗi việc ghi rõ **kiểm gì và báo gì** ("báo tôi nếu cần restart Claude Code", "chưa apply cho tới khi tôi đưa webhook"). Kết quả: phát hiện kubeconfig MCP vẫn trỏ minikube đã chết và tạo lại quyền read-only cho kind (Role chỉ trong namespace, không có secrets).
- Yêu cầu harvest script "gọi đúng `query_range` như `verify.py:622-633`" cho một script tái hiện đúng luật khớp của verifier; trong lúc thử, nó lộ ra lỗi label `endpoint` bị đổi thành `exported_endpoint` (panel 1 nhóm sai), sửa trước khi có RCA nào dùng.
- "Không commit webhook" + đọc từ Secret cho ra cấu hình Alertmanager đọc file mount; `amtool check-config` và routing test đạt trước khi apply.

**What I changed**:
- Bản nháp MLOps notes chỉ là bản nháp: tôi đọc và thay toàn bộ bằng lời của mình ở bước cuối Day 4 (đã ghi trong prompt: "Tôi sẽ đọc và sửa lại").

---

## Prompt 4 - Áp Secret Slack có sẵn và thay mật khẩu Grafana đã lộ, chỉ một lần helm upgrade

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.284, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `observability/monitoring/apply-alertmanager-slack.sh`, `create-grafana-admin-secret.sh`, `kube-prometheus-stack.values.yaml`; commit `d1a5284`; số scrape trước/sau upgrade từ Prometheus.
**Time**: 29/09/2026, 20:57 (+07)

**Prompt**:
````
2 việc trước khi chạy incident:

1. Secret monitoring/alertmanager-slack (key webhook_url) TÔI ĐÃ TẠO SẴN. Không tạo lại, không đọc SLACK_WEBHOOK_URL. Sửa apply-alertmanager-slack.sh: bỏ bước tạo Secret, chỉ kiểm Secret tồn tại và có key webhook_url (không in giá trị), rồi helm upgrade.

2. Mật khẩu admin Grafana đã bị push lên repo public trong kube-prometheus-stack.values.yaml. Sửa trong CÙNG lần helm upgrade với bước 1 (chỉ upgrade 1 lần):
   - Tạo Secret grafana-admin trong namespace monitoring với mật khẩu MỚI sinh ngẫu nhiên (không dùng lại "insighthub" vì nó còn trong lịch sử git), không in ra log.
   - values dùng grafana.admin.existingSecret, xóa adminPassword khỏi file values.
   - Quét lại toàn repo xem còn credential nào khác bị commit không.
   - Commit + push.

Helm upgrade: kiểm Prometheus pod có bị restart không. Nếu có thì báo tôi mất bao nhiêu scrape baseline.

Sau upgrade: bắn test alert (--test), báo tôi để tôi mở Slack #alerts chụp ảnh evidence MH6.

Khi count scrape up{job="insighthub-api"} ≥115 thì báo tôi, CHƯA tự chạy incident.
````

**Why it worked**:
- Ranh giới quyền rõ: "Secret … TÔI ĐÃ TẠO SẴN. Không tạo lại, không đọc" nên script chỉ kiểm **tên key**, không bao giờ đụng giá trị.
- "Kiểm Prometheus pod có bị restart không. Nếu có thì báo tôi mất bao nhiêu scrape" buộc agent đo tác động lên baseline: Prometheus 0 restart, không mất scrape nào.
- Lệnh quét toàn repo tìm credential khác cho ra kết luận cụ thể: lịch sử git không có key/token/webhook, còn mật khẩu Postgres lab ở `docker-compose.yml` và `values.yaml` của local-deps.

**What I changed**:
- "Chỉ upgrade 1 lần" không giữ được: rolling update Grafana bị Pending vì node đã 99% CPU requests, phải chuyển sang `Recreate` và chạy lại lệnh để chốt release (revision 3). Đã báo trung thực.
- Mật khẩu cũ vẫn nằm trong lịch sử git của repo public; đã vô hiệu (401) chứ không viết lại lịch sử.

---

## Prompt 5 - Chạy 3 incident, RCA bằng subagent mù, đối chiếu sau

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.284, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `scripts/chaos/inject-*.sh`, `evidence/chaos-*-window.json`, `evidence/incident-{1,2,3}.json`, `observability/rca-prompt.md`; 43 sample khớp `query_range`.
**Time**: 30/09/2026, 02:20 (+07)

**Prompt**:
````
Slack test alert đã OK (FIRING + RESOLVED đều tới #alerts, tôi đã chụp ảnh). Chạy 3 incident theo thứ tự, mỗi incident làm đủ vòng dưới đây rồi mới sang cái tiếp.

Với mỗi incident:
1. Chạy script inject (incident 1: inject-llm-latency.sh, incident 2: inject-queue-backlog.sh, incident 3: inject-error-burst.sh). Script tự revert và ghi evidence/chaos-<tên>-window.json.
2. Xác nhận alert FIRING trong Prometheus và gửi tới Slack. Báo tôi NGAY lúc alert firing để tôi chụp ảnh Slack + Grafana dashboard.
3. Chờ phục hồi (alert resolved).
4. RCA: chạy bằng SUBAGENT MỚI (không có ngữ cảnh phiên này, không biết lỗi đã tiêm), đưa đúng khối prompt trong observability/rca-prompt.md với ALERT_NAME + STARTED_AT + ENDED_AT + INCIDENT_ID. Subagent dùng Prometheus MCP + Kubernetes MCP, samples lấy bằng scripts/chaos/harvest-samples.py (không gõ tay).
5. Sau khi có RCA, bạn mới đối chiếu với lỗi đã tiêm, ghi thêm trường injected_fault và đánh giá subagent đoán đúng hay sai. Không sửa hypotheses của subagent.
6. Ghi evidence/incident-<n>.json, kiểm bằng logic verify.py (3 incident_id khác nhau, samples nằm trong cửa sổ, khớp query_range).
7. Nghỉ ít nhất 10 phút trước incident tiếp theo để band ổn định (band dùng offset 10m).

Sau cả 3 incident:
- Cập nhật DAY4-CHECKLIST.md MH6-MH10.
- Commit + push HẾT mọi thay đổi trong observability/, scripts/, infra/ (đóng băng source).
- CHỈ SAU ĐÓ: ghi evidence/day4.json mode real (7 artifact: dashboard, rules, rule_tests, rca, rca_2, rca_3, mlops_notes) và chạy scripts/verify-day-4.sh --prometheus-url http://localhost:9090, lưu output vào evidence/.

Lưu ý: RCA phải còn tươi ≤24h lúc verify, Prometheus phải sống lúc verify. Không xóa kind cluster.
````

**Why it worked**:
- Vòng 7 bước lặp lại cho từng incident, có **điểm dừng báo người dùng đúng lúc alert FIRING** để chụp ảnh Slack và Grafana.
- "RCA bằng SUBAGENT MỚI, không biết lỗi đã tiêm" và "không sửa hypotheses của subagent" giữ cho RCA là điều tra độc lập: subagent chỉ nhận đúng khối prompt, Prometheus/K8s MCP và harvest script.
- Kiểm bằng logic `verify.py` trước khi ghi evidence bắt được sự cố thật: guard baseline của `lib.sh` lấy nhầm series đầu tiên sau khi pod api đổi, và quy tắc 5 của prompt RCA mâu thuẫn với verifier (baseline phải nằm trong cửa sổ). Cả hai đã sửa và ghi vào checklist.

**What I changed**:
- Không sửa `hypotheses`, `ruled_out`, `samples` của subagent; chỉ thêm `injected_fault` và đánh giá (đúng / đúng nguyên nhân gốc, sai nhẹ cơ chế).
- Node 2 CPU không surge được pod api nên `maxSurge: 0` được vá trực tiếp; đến bước cuối Day 4 mới đưa vào chart (`values-local.yaml`).

---
