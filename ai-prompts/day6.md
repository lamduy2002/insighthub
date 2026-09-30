# Day 6 AI Prompts

Ba prompt thiết kế dưới đây là **nguyên văn** những gì tôi đã gửi trong phiên làm Day 6 (30/09/2026), chép
trực tiếp từ transcript (chỉ bỏ thẻ bao `<pasted_content>` của giao diện), không chỉnh cho đẹp và không chép
từ prompt pack của giảng viên. Các tin nhắn ngắn còn lại chỉ là nhắc trạng thái. Phiên dùng Claude Code
v2.1.285 (`claude --version`), model Sonnet 5.5 (`claude-sonnet-5-5`), đăng nhập Claude Team subscription
(không dùng API key). Giờ lấy theo mốc commit trong repo nên ghi "khoảng".

Lưu ý trung thực: prompt 2 chọn provider Zenlayer, nhưng key giảng viên cấp đã hết hạn (`GET /v1/models`
trả 401 "Expired API key ... 2026-09-27"). Prompt 3 chuyển hẳn sang Ollama local. Zenlayer chưa từng được gọi
để sinh bằng chứng nào.

---

## Prompt 1 - Khảo sát verifier Day 6 và lập checklist trước khi ghi file

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.285, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription
**Context / Evidence**: spec §0.5, §4, §10; `scripts/VERIFICATION_CONTRACT.md` (Day 6); `scripts/verify.py` (`REQUIRED_TESTS` 36-42, `eval_report` 696-721, `cost_report` 724-752, `day6` 755-783); `docs/Guide_Local_AWS_Cost_DO2603.md`; `GETTING_STARTED.md` mục 4; `security/`; `sample-docs/`; `api/app/core/config.py`; `chatops-bot/app/`
**Time**: 30/09/2026, khoảng 17:38 (+07)

**Prompt**:
````
Bắt đầu Day 6 (spec §10: Security, Governance & FinOps). Hạn nộp: HẾT HÔM NAY. Mục tiêu: đạt L3 cả Dim 6 (Security) và Dim 7 (FinOps), đủ Must-have MH1-MH12. Bỏ Should/Nice-have trừ khi verifier bắt buộc.

Tạo branch day6-security từ day5-chatops.

RÀNG BUỘC CỨNG:
- KHÔNG làm hỏng Prometheus/kind của Day 4 (cần sống tới 02:05 ngày 01/10). Không xóa cluster, không xóa PVC Prometheus, không đổi PrometheusRule Day 4.
- Mọi secret (key LLM, LiteLLM master key, virtual key) chỉ nằm trong file .env đã gitignore hoặc K8s Secret. Không in ra log/chat, không commit.
- Không dùng fixture làm bằng chứng LLM thật (verifier từ chối hash/extractive/mock/fixture).
- Không tạo HIGH giả để "sửa"; initial scan ghi trung thực.

LƯỢT NÀY: CHỈ KHẢO SÁT + lập infra/DAY6-CHECKLIST.md. KHÔNG code, KHÔNG cài gì, KHÔNG gọi LLM.

Đọc: spec §0 (nhất là 0.5 về 3 workload qua gateway), §4, §10 (toàn bộ, gồm Acceptance 10.5, Rubric 10.6, Pitfalls 10.7, Submission 10.8, Self-Check 10.9); scripts/VERIFICATION_CONTRACT.md phần Day 6; scripts/verify.py phần day6 + scripts/verify-day-6.sh; docs/lab-guides/ (file Day 6 nếu có); docs/Guide_Local_AWS_Cost_DO2603.md; GETTING_STARTED.md mục 4 (chuyển real provider, cấm trộn fixture/real cùng DB); security/ (skeleton có gì); sample-docs/ (tìm poisoned-doc); api/app/core/config.py và services/llm.py (cách app gọi LLM, biến OPENAI_BASE_URL, embedding identity); chatops-bot/app/ (bot đang rule-based, chưa gọi LLM); infra/DAY4-CHECKLIST.md và DAY5-CHECKLIST.md (hiện trạng cluster, Grafana, bot).

Từ CODE verifier, trả lời chính xác (trích dòng code):
1. verify.py day6 kiểm đúng những gì? Liệt kê từng assertion.
2. REQUIRED_TESTS[6] gồm test tên gì, đặt ở đâu?
3. Format chính xác của 4 artifact: dataset, eval_initial, eval_final, cost (trường bắt buộc, điều kiện category injection+benign, cách kiểm request_id/provider/model thật, cách kiểm phép tính cost, budget_usd, resource_usage cho entry chi phí 0).
4. Observations {run_id, eval_final, cost} ghi thế nào, test phải làm gì.
5. Dataset/eval của verifier có phải chính là Promptfoo không, hay là 2 thứ riêng (Promptfoo cho MH1-MH5, dataset JSON cho verifier)? Nêu cách làm 1 lần dùng cho cả 2 nếu được.

Từ CODE app và môi trường:
6. App chuyển sang real provider qua LiteLLM thế nào: biến nào (LLM_PROVIDER=openai, OPENAI_BASE_URL, key, LLM_MODEL, EMBEDDING_PROVIDER/MODEL)? Embedding có bắt buộc phải real khi RAG_MODE=real không? Đổi embedding identity cần DB/schema mới: đề xuất chạy InsightHub real ở đâu (namespace mới trên kind, hay docker compose project riêng) mà không đụng Day 4.
7. Poisoned-doc có sẵn trong sample-docs không, nội dung tấn công kiểu gì? Kế hoạch discover (upload → retrieval → chat bị ảnh hưởng) và fix theo nhiều lớp (sanitization, prompt hardening, guardrail).
8. Guardrail: so sánh NeMo Guardrails / Llama Guard 3 / guardrail của LiteLLM theo độ nặng trên máy 2 vCPU và khả năng chạy thật. Đề xuất 1 lựa chọn, kèm cách chứng minh runtime allowed/blocked (MH6).
9. LiteLLM: image/version pin, cần Postgres cho budget (pitfall 10.7), cách tạo 3 virtual key (insighthub, chatops-bot, coding-workflow) có max_budget, cách test budget allowed/denied và đo overshoot khi gọi đồng thời (NFR #2), cách lấy attribution theo từng key/request (NFR #5), audit mọi LLM call (NFR #3).
10. ChatOps bot cần traffic LLM thật qua key riêng: đề xuất tính năng tối thiểu (ví dụ tóm tắt/giải thích câu trả lời bằng LLM) mà không phá 5 test bắt buộc Day 5.
11. Coding workflow theo mục 0.5: Claude Code (đăng nhập Team subscription) có route được qua LiteLLM không? Nếu không, thiết kế script coding workflow qua gateway với key coding-workflow: nhận context repo → đề xuất thay đổi → lưu diff → chạy test → ghi attribution. Ghi rõ nhánh nào được chọn.
12. Cost dashboard Grafana: LiteLLM bản open-source có /metrics Prometheus không (kiểm theo version pin)? Nếu không, cách xuất cost rate vào Prometheus. Panel phải tên "LLM Cost".
13. MH11 AWS Budgets: Day 6 không dùng AWS thì ghi "không áp dụng" kèm lý do theo Guide, đúng không?
14. RAM/CPU hiện tại: còn bao nhiêu, cần tắt gì (bot Day 5, ngrok, load generator Day 4) để đủ chỗ cho LiteLLM + Postgres + InsightHub real + guardrail + Promptfoo, mà Prometheus Day 4 vẫn sống.

CHECKLIST phải có: MH1-MH12, 12 dòng Acceptance 10.5, 5 NFR 10.3, Rubric L3 của cả 2 Dim, mỗi dòng ghi nguồn + trạng thái; 4 artifact verifier; danh sách OWASP LLM Top 10 v2025 + Agentic ASI01-04 sẽ cover; khung threat model 6+ threat; những thứ CẦN TÔI CUNG CẤP (thông tin provider: base URL, tên model chat, tên model embedding, giới hạn chi phí; cách tôi đặt key vào .env); rủi ro; ước lượng thời gian từng phần; thứ tự đóng băng source trước khi tạo evidence/day6.json.

Trình bày checklist cho tôi duyệt TRƯỚC KHI ghi file. Hỏi tôi thông tin provider nếu cần. Không code ở lượt này.
````

**Kết quả / Quyết định**: Agent trình bày bản nháp checklist; tôi duyệt ở prompt 2. Phát hiện quan trọng: verifier chạy LLM thật trong pytest lúc chấm; node kind đã 99% CPU request nên gateway phải chạy compose trên host; `eval_initial` phải mang digest nguồn cuối.

---

## Prompt 2 - Duyệt checklist, chốt provider, ngân sách, thứ tự làm

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.285, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription
**Context / Evidence**: bản nháp checklist từ prompt 1; `infra/DAY6-CHECKLIST.md`
**Time**: 30/09/2026, khoảng 17:48 (+07)

**Prompt**:
````
Duyệt checklist, chốt:

1-3. Provider: Zenlayer (key giảng viên cấp), base URL https://gateway.theturbo.ai. Tôi đã ghi UPSTREAM_API_KEY và UPSTREAM_BASE_URL vào .env gốc. Tự xác định đường dẫn API chuẩn OpenAI (thử /v1/models), gọi GET models (không tốn tiền) để lấy danh sách, chọn: 1 model chat rẻ cho eval + bot, 1 model mạnh hơn cho coding (nếu có), 1 model embedding hỗ trợ 1024 chiều. Nếu KHÔNG có embedding 1024 chiều: báo tôi ngay, đề xuất phương án (ví dụ Ollama mxbai-embed-large qua LiteLLM) kèm RAM cần dùng. Không phải Bedrock → MH11 không áp dụng.
4. Giá: tự tra trang giá của provider, ghi URL + ngày tra. Không tìm được thì báo tôi.
5. Ngân sách: tổng Day 6 tối đa 3 USD. Mỗi key: insighthub 1.2, promptfoo 1.0, chatops-bot 0.3, coding-workflow 0.5. Dừng báo tôi nếu tổng spend vượt 2 USD.
6. Promptfoo: cho phép remote generation. Dùng key thứ 4 riêng cho Promptfoo.
Đồng ý các mặc định: thêm object K8s mới (không sửa cái cũ), bot chứng minh bằng event tự ký cục bộ (không Slack/ngrok), pin LiteLLM theo digest, không tắt mysqld, eval_initial có thêm scan_source_sha256 kèm ghi chú.

Làm theo thứ tự ưu tiên, làm đủ hết, không cắt:
1. Compose + LiteLLM + Postgres + 4 key + InsightHub real (reindex).
2. Promptfoo config + generate ≥50 ca + initial scan (ghi trung thực).
3. Discover poisoned-doc + 3 fix (mỗi fix 1 commit có diff/test) + guardrail litellm_content_filter.
4. Final scan no HIGH/CRITICAL + dataset/eval converter + tests/milestones/day6 (3 test bắt buộc) + test budget/concurrency.
5. Threat model 8 threat.
6. Grafana panel "LLM Cost".
7. Bot summarize + coding workflow (có traffic thật qua key riêng).
8. Freeze → verify → evidence → ai-prompts/day6.md → PR (base day5-chatops) → evidence/day6-submission.md.

Tạo branch day6-security, ghi checklist, rồi LÀM LUÔN. Chỉ dừng hỏi khi có quyết định thiết kế hoặc rủi ro chi phí. Báo ngắn (≤5 dòng) sau mỗi mục, ghi tổng spend hiện tại.
````

**Kết quả / Quyết định**: Agent tạo branch và checklist, gọi `GET /v1/models` (miễn phí) và nhận 401 vì key hết hạn, nên dừng báo thay vì tự đổi provider.

---

## Prompt 3 - Chuyển hẳn sang Ollama local

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.285, Sonnet 5.5 (`claude-sonnet-5-5`), Claude Team subscription
**Context / Evidence**: `scripts/VERIFICATION_CONTRACT.md` ("Ollama is a real model provider and is valid"); `GETTING_STARTED.md` mục Ollama; `infra/DAY6-CHECKLIST.md`
**Time**: 30/09/2026, khoảng 17:55 (+07)

**Prompt**:
````
Không chờ key nữa. Chuyển hẳn sang Ollama local làm provider thật qua LiteLLM (VERIFICATION_CONTRACT: "Ollama is a real model provider and is valid"). Bỏ UPSTREAM_API_KEY/UPSTREAM_BASE_URL khỏi thiết kế.

Trước khi tải model:
1. Đo RAM/CPU hiện tại, chọn model chat nhỏ nhất đủ dùng (ưu tiên qwen2.5 0.5b hoặc 1.5b, bản quantized) + embedding mxbai-embed-large (1024 chiều, đúng adapter starter). Báo tôi RAM dự kiến sau khi chạy đủ stack (Ollama + LiteLLM + Postgres + InsightHub real) và phần còn trống, rồi LÀM LUÔN nếu còn ≥500MB dư.
2. Chạy Ollama bằng docker (pin version, đặt mem_limit), ghi digest model đã tải (theo GETTING_STARTED mục Ollama).
3. Cost = 0 → mọi entry trong cost report phải có resource_usage đo thật (measurement_source, duration_seconds, memory_peak_bytes). budget_usd vẫn đặt số dương. max_budget cho 4 virtual key vẫn đặt để chứng minh enforcement (dùng giá giả định cấu hình trong LiteLLM hoặc budget theo token, chọn cách LiteLLM hỗ trợ thật và ghi rõ lý do).
4. Promptfoo: cho phép remote generation. Grader dùng chính model Ollama qua gateway (key promptfoo). Nếu grader model nhỏ quá cho kết quả vô nghĩa thì báo tôi.

Sau đó làm tiếp đủ 8 mục theo thứ tự đã chốt. Báo ngắn (≤5 dòng) sau mỗi mục.
````

**Kết quả / Quyết định**: RAM còn ≈1.8GB khi chạy đủ stack nên làm luôn: Ollama 0.33.3 (mem_limit 1.4GB, `OLLAMA_MAX_LOADED_MODELS=1`), `qwen2.5:0.5b` + `mxbai-embed-large`, LiteLLM v1.103.1 pin digest. Giá giả định (shadow price) trong LiteLLM để `max_budget` chạy được, cost thật = 0 nên cost report dùng `resource_usage` đo từ cgroup. Grader `qwen2.5:0.5b` cho kết quả vô nghĩa, đã thay bằng `qwen2.5:1.5b` (run 1 lưu ở `evidence/run1/`).
