# Day 6 Checklist — Security, Governance & FinOps (DO2603)

Checklist duy nhất cho Day 6 (spec §10). Hạn nộp 2026-09-30 23:59. Khẳng định về verifier trích dòng `scripts/verify.py`. Ký hiệu: ✅ xong · ⚪ không áp dụng · ⚠️ lệch/giới hạn. Kết quả scan, verify và bảng triage từng ca nằm ở `evidence/day6-submission.md` (file này thuộc digest nguồn nên không chứa số liệu chạy sau đóng băng).

## Nguồn đã đọc
Spec §0 (0.4, 0.5), §3, §4, §10 · `scripts/VERIFICATION_CONTRACT.md` (Day 6) · `scripts/verify.py` (`REQUIRED_TESTS` 36-42, `evidence` 310-318, `validate_junit` 352-364, `run_tests` 367-396, `eval_report` 696-721, `cost_report` 724-752, `day6` 755-783, `main` 865-919) · `docs/lab-guides/Day6-*.md` · `docs/Guide_Local_AWS_Cost_DO2603.md` · `GETTING_STARTED.md` §4 · `security/` · `sample-docs/` · `api/app/core/config.py`, `services/{llm,embeddings,retrieval}.py` · `chatops-bot/app/` · `infra/DAY4-CHECKLIST.md`, `DAY5-CHECKLIST.md`.

## Quyết định và lệch so với kế hoạch ban đầu
1. **Provider**: Zenlayer bị bỏ (key giảng viên cấp đã hết hạn 2026-09-27, `GET /v1/models` trả 401; chưa từng gọi để sinh bằng chứng). Chuyển hẳn sang **Ollama local** qua LiteLLM (`VERIFICATION_CONTRACT`: Ollama là provider thật hợp lệ): chat `qwen2.5:0.5b`, embedding `mxbai-embed-large` (1024 chiều). Không dùng AWS ⇒ MH11 ⚪.
2. **Giá**: Ollama không có phí ⇒ cost report dùng `cost_usd=0` + `resource_usage` đo thật (cgroup). LiteLLM dùng **giá giả định (shadow price)** chỉ để `max_budget`, attribution và dashboard hoạt động (`security/MODELS.md`).
3. **Gateway chạy docker compose trên host** (project `insighthub-day6`), không trong kind (node đã 99% CPU request). Day 4 không bị sửa: chỉ thêm namespace `llm-gateway` (Service/Endpoints/ServiceMonitor) và ConfigMap dashboard mới.
4. **3 virtual key** (insighthub 1.2, chatops-bot 0.3, coding-workflow 0.5 shadow-USD). Key `promptfoo` đã bỏ: grader/generator Promptfoo (`qwen2.5:1.5b`) gọi **thẳng Ollama** `127.0.0.1:11434`, cố ý ngoài gateway vì là công cụ đánh giá, không phải workload, và prompt của nó chứa chính các tấn công (guardrail default_on sẽ chặn nó).
5. **Guardrail** = `litellm_content_filter`, `default_on: true` cho MỌI key (key-level guardrail là enterprise: HTTP 403 ở v1.103.1). Client không tắt được; có test.
6. **Bot**: event tự ký cục bộ, không Slack/ngrok. **Coding workflow**: nhánh B (workflow API), không khai Claude Code/Team subscription đã route qua gateway.
7. **Dataset**: 22 ca, một tiêu chí thống nhất cho mọi ca hỏi-đáp hợp lệ (không bị chặn + answer không rỗng + có sources); facts chỉ báo cáo. Không xóa/hạ ca nào (đã từng xóa 2 ca rồi khôi phục theo yêu cầu, commit `5cc7a31`).
8. **Initial/final** cùng `dataset_sha256`; `eval_initial` mang `scan_source_sha256` (digest commit `e99d606`, mã chạy thật lúc scan) và `source_sha256` = digest cuối để verifier bind.
9. Chỉ MH1-MH12; bỏ Should/Nice-have.

## A. Must-have MH1-MH12 (§10.4)
| # | Yêu cầu | Trạng thái |
|---|---|---|
| MH1 | `security/promptfooconfig.yaml` | ✅ Promptfoo 0.123.1 pin + lockfile |
| MH2 | Coverage direct/indirect, RAG poisoning, PII, excessive agency | ✅ 8 plugin ID hợp lệ (bảng ở `security/README.md`); `rag-poisoning` dùng `llm-rubric` tự viết (bản pin không có grader cho nó); strategy chỉ `basic` ⚠️ |
| MH3 | Initial scan `red-team-report.html` | ✅ `evidence/red-team-report-initial.html` (trên stack chưa sửa) |
| MH4 | Fix iterations (commit) | ✅ sanitize `55aad6e`, prompt/retrieval/output `e55b1a6`, temperature 0, guardrail, guardrail default-on |
| MH5 | Final scan no HIGH/CRITICAL | xem `evidence/day6-submission.md` (kết quả và triage từng ca) |
| MH6 | Guardrails runtime allowed/blocked | ✅ `test_injection_blocked`, `test_benign_allowed`, `test_insighthub_key_cannot_skip_the_guardrail` |
| MH7 | LiteLLM deployed | ✅ v1.103.1 pin digest; `/health/liveliness` 200 (route `/healthz` của spec không tồn tại ⚠️) |
| MH8 | 3 key `max_budget`, trace, allowed/denied, attribution | ✅ `evidence/day6-budget-proof.json` (HTTP 429 trên từng key khi hạ trần dưới spend), ledger coding workflow, trace bot |
| MH9 | InsightHub qua gateway, audit log | ✅ `OPENAI_BASE_URL=litellm`, log JSON `llm_call` + header `X-LLM-Request-Id` |
| MH10 | Dashboard Grafana "LLM Cost" | ✅ `observability/grafana-dashboards/llm-cost.json`, Prometheus Day 4 scrape `up=1`, cả 5 panel có dữ liệu |
| MH11 | AWS Budgets | ⚪ Day 6 không dùng AWS (`aws_used=false`, Guide local/AWS) |
| MH12 | `security/threat-model.md` | ✅ 9 threat, 6 lớp phòng thủ, bảng OWASP |

## B. Acceptance §10.5 (12 dòng)
| # | Dòng | Trạng thái |
|---|---|---|
| 1 | yq `promptfooconfig.yaml` hợp lệ | ✅ |
| 2 | `redteam generate` ≥50 ca | ✅ 63 ca |
| 3 | `redteam run` → initial report | ✅ |
| 4 | Fix iterations có diff/test/lý do | ✅ |
| 5 | Final scan no HIGH/CRITICAL | xem submission |
| 6 | Guardrails config tồn tại | ✅ `security/litellm/config.yaml` |
| 7 | Health gateway 200 | ✅ `/health/liveliness` |
| 8 | 3 key + trace + denial + attribution | ✅ |
| 9 | InsightHub dùng `LITELLM_API_KEY` | ⚠️ biến thực tế là `OPENAI_API_KEY` (adapter starter), giá trị là virtual key insighthub |
| 10 | Grafana "LLM Cost" cost rate | ✅ |
| 11 | `insighthub-llm-monthly` | ⚪ không dùng AWS |
| 12 | threat-model ≥6 threat | ✅ |

## C. NFR §10.3
| # | Yêu cầu | Trạng thái |
|---|---|---|
| 1 | HIGH/CRITICAL được ghi lại | ✅ bảng finding initial/final trong submission |
| 2 | Budget test tuần tự + đồng thời, ghi cửa sổ/overshoot | ✅ `test_budget_enforced`, `day6-budget-proof.json` (overshoot đo ≈1.2 call, spend hiển thị sau ≤14s) |
| 3 | Audit mọi LLM call | ✅ spend logs (không lưu nội dung) + log JSON app; trace bot/coding có request_id |
| 4 | Threat model ≥6 threat | ✅ |
| 5 | Cost attribution theo request | ✅ tag `x-litellm-tags` + `x-litellm-call-id`, tra `/spend/logs?request_id=` |

## D. Rubric L3
- Dim 6 Security: Promptfoo no-HIGH (theo submission), threat model ✅, guardrails enabled ✅.
- Dim 7 FinOps: cost report đạt budget ✅, dashboard ✅, gateway enforcement ✅.
- Không nhắm L4 (không có PII detector tiếng Việt, guardrail regex nông).

## E. Giới hạn đã biết
- Guardrail là regex/keyword (nông). Model 0.5B yếu nên chất lượng trả lời thấp; dataset không chấm facts.
- Grader 1.5B có thể nhiễu; submission triage từng ca fail.
- Verifier chạy LLM thật mỗi lần: phải truyền `--test-timeout 1800` (mặc định 120s không đủ).
- `chatops-bot/` đổi ⇒ `source_sha256` của Day 5 lệch; bằng chứng Day 5 là output đã lưu ở branch `day5-chatops`.
- Dashboard/Grafana là port-forward local, không có URL công khai.

## F. Thứ tự đóng băng (đã thực hiện)
Sửa mọi nguồn ⇒ commit ⇒ `verify.py fingerprint` ⇒ eval final + cost ⇒ `make_day6_json.py` ⇒ `verify-day-6.sh --test-timeout 1800` ⇒ lưu output. Sửa file nào trong digest sau bước fingerprint đều phải lặp lại từ đó.
