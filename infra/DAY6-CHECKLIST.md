# Day 6 Checklist — Security, Governance & FinOps (DO2603)

Checklist duy nhất cho Day 6 (spec §10). Hạn nộp 2026-09-30 23:59. Khẳng định về verifier trích dòng `scripts/verify.py`. Ký hiệu: ⏳ chưa làm · ✅ xong · ⚪ không áp dụng · ❓ cần người dùng · ⚠️ rủi ro.

## Nguồn đã đọc
Spec §0 (0.4, 0.5), §3, §4, §10 · `scripts/VERIFICATION_CONTRACT.md` (Day 6) · `scripts/verify.py` (`REQUIRED_TESTS` 36-42, `evidence` 310-318, `artifact` 321-332, `validate_junit` 352-364, `run_tests` 367-396, `eval_report` 696-721, `cost_report` 724-752, `day6` 755-783, `main` 865-919) · `scripts/verify-day-6.sh` · `docs/lab-guides/Day6-*.md` · `docs/Guide_Local_AWS_Cost_DO2603.md` · `GETTING_STARTED.md` §4 · `security/` · `sample-docs/` · `api/app/core/config.py`, `api/app/services/{llm,embeddings,retrieval}.py` · `chatops-bot/app/` · `infra/DAY4-CHECKLIST.md`, `DAY5-CHECKLIST.md`.

## Quyết định đã chốt (2026-09-30)
1. Provider: Zenlayer (`https://gateway.theturbo.ai`, key giảng viên cấp), khóa ở `.env` gốc (gitignore). Không phải Bedrock ⇒ không dùng AWS.
2. Ngân sách tổng ≤ 3 USD; **dừng báo người dùng nếu tổng spend > 2 USD**. Key: insighthub 1.2 · promptfoo 1.0 · chatops-bot 0.3 · coding-workflow 0.5.
3. Promptfoo: cho phép remote generation; key thứ 4 riêng.
4. Gateway LiteLLM chạy docker compose host (project `insighthub-day6`), vì node kind đã 99% CPU request. Không đụng Day 4 (không xóa cluster/PVC, không đổi PrometheusRule).
5. Bot chứng minh bằng event tự ký cục bộ (không Slack/ngrok). Coding workflow = nhánh B (workflow API), không khai host subscription đã route.
6. Guardrail = `litellm_content_filter` (regex/keyword, lớp nông, nhắm L3).
7. `eval_initial`: `source_sha256` = digest cuối (để khớp `verify.py:699`), kèm `scan_source_sha256` = digest lúc scan thật và ghi chú.
8. Chỉ MH1-MH12; bỏ Should/Nice-have.

## A. Must-have MH1-MH12 (§10.4)
| # | Yêu cầu | Kế hoạch | TT |
|---|---|---|---|
| MH1 | `security/promptfooconfig.yaml` | pin Promptfoo 0.123.1 + lockfile | ⏳ |
| MH2 | Coverage direct/indirect, RAG poisoning, PII, excessive agency | plugin `indirect-prompt-injection`, `rag-poisoning`, `rag-document-exfiltration`, `pii:direct`, `excessive-agency`, `prompt-extraction`, `hijacking`; strategy `jailbreak-templates`; bảng mapping | ⏳ |
| MH3 | Initial scan `red-team-report.html` | `redteam run` thật, provider upload+retrieve | ⏳ |
| MH4 | Fix iterations (commits) | ≥3 commit có diff+test, không commit rỗng | ⏳ |
| MH5 | Final scan no HIGH/CRITICAL | cùng dataset | ⏳ |
| MH6 | Guardrails runtime allowed/blocked | `litellm_content_filter` + 2 test | ⏳ |
| MH7 | LiteLLM deployed | pin digest, health thật | ⏳ |
| MH8 | 3 virtual key `max_budget`, trace 3 workload, allowed/denied, attribution | + key thứ 4 cho Promptfoo | ⏳ |
| MH9 | InsightHub qua gateway, audit log | `OPENAI_BASE_URL=litellm` | ⏳ |
| MH10 | Dashboard Grafana "LLM Cost" | ServiceMonitor + ConfigMap mới | ⏳ |
| MH11 | AWS Budgets | `aws_used=false` (Guide) | ⚪ |
| MH12 | `security/threat-model.md` | 8 threat | ⏳ |

## B. Acceptance §10.5 (12 dòng)
| # | Dòng | TT |
|---|---|---|
| 1 | yq `promptfooconfig.yaml` hợp lệ | ⏳ |
| 2 | `redteam generate` ≥50 ca | ⏳ |
| 3 | `redteam run` → initial report | ⏳ |
| 4 | Fix iterations có diff/test/lý do | ⏳ |
| 5 | Final scan no HIGH/CRITICAL | ⏳ |
| 6 | Guardrails config tồn tại | ⏳ |
| 7 | Health gateway 200 (spec `/healthz`; ghi route thực) | ⏳ ⚠️ |
| 8 | 3 key + trace + denial + attribution | ⏳ |
| 9 | InsightHub dùng `LITELLM_API_KEY` (code dùng `OPENAI_API_KEY`, ánh xạ ở compose, ghi lệch) | ⏳ |
| 10 | Grafana "LLM Cost" cost rate | ⏳ |
| 11 | `insighthub-llm-monthly` | ⚪ |
| 12 | threat-model ≥6 threat | ⏳ |

## C. NFR §10.3
| # | Yêu cầu | TT |
|---|---|---|
| 1 | HIGH/CRITICAL được ghi lại | ⏳ |
| 2 | Budget test tuần tự + đồng thời, ghi cửa sổ/overshoot | ⏳ |
| 3 | Audit mọi LLM call | ⏳ |
| 4 | Threat model ≥6 threat + mitigation | ⏳ |
| 5 | Cost attribution theo request (tag) | ⏳ |

## D. Rubric L3
- Dim 6 Security (8-9đ): Promptfoo no-HIGH, có threat model, guardrails enabled. ⏳
- Dim 7 FinOps (5-6đ): cost report đạt budget, có dashboard, gateway enforcement. ⏳
- Pass = cả hai L3. Không nhắm L4.

## E. Sự thật từ verifier
- Test bắt buộc: `test_injection_blocked`, `test_benign_allowed`, `test_budget_enforced` tại `tests/milestones/day6/test_*.py` (`verify.py:41`, 368-370). Không skip/xfail; pytest `-c /dev/null`, không plugin async.
- Test phải gọi LLM thật toàn bộ dataset và ghi `{run_id, eval_final, cost}` vào `INSIGHTHUB_VERIFY_OBSERVATIONS` (775-780) ⇒ mỗi lần verify tốn tiền; `--test-timeout` mặc định 120s ⇒ gọi song song/tăng timeout.
- Artifact: `dataset` `{cases:[{id,category,input,expected}]}` (cần `injection`+`benign`); `eval_*` `{mode,observed_at,source_sha256,dataset_sha256,results:[{case_id,passed,severity,provider,model,request_id,input_tokens,output_tokens}]}`; `cost` `{mode,observed_at,source_sha256,currency:"USD",budget_usd,total_usd,entries:[{request_id,tokens,rates,cost_usd,(resource_usage)}]}`.
- `provider+model` không chứa `hash|extractive|fallback|fixture|mock|dummy|fake` (716). `cost_usd` không làm tròn (abs_tol 1e-9). Ca cost 0 cần `resource_usage` đo thật (742-747).
- `mode` phải `real`, `eval_*.observed_at` ≤24h, initial ≤ final (772).
- Verifier không kiểm Promptfoo, guardrail, LiteLLM, key, dashboard, threat model.

## F. OWASP
- LLM Top 10 v2025: *test* LLM01, 02, 06, 07, 08, 10; *chỉ ghi* 03, 04, 05, 09.
- Agentic ASI01-04 ghi trong threat model (tên đối chiếu nguồn OWASP khi viết).

## G. Threat model (8)
T1 indirect injection qua upload · T2 direct injection/jailbreak · T3 lộ system prompt/secret · T4 lộ PII/tài liệu · T5 excessive agency qua bot · T6 bill shock/lạm dụng key · T7 bypass key (gọi provider trực tiếp) · T8 coding agent áp diff chưa duyệt.

## H. Rủi ro
| Rủi ro | Mức |
|---|---|
| Hạn 23:59, đường găng ≈6h | 🔴 |
| Chi phí: verify gọi thật mỗi lần; ngưỡng dừng 2 USD | 🔴 |
| Key upstream hết hạn (phát hiện 17:50: hết hạn 2026-09-27) | 🔴 |
| Embedding 1024 chiều chưa xác nhận | 🟡 |
| LiteLLM 1.103.1 ra hôm nay; lùi 1.102.2 nếu cần | 🟡 |
| Guardrail regex chặn nhầm benign ⇒ sanitize (L1) trước gateway | 🟡 |
| Embedding call ngoài cost verifier ⇒ khai `embedding_usd` riêng | 🟡 |
| Thêm object K8s vào cluster Day 4 (chỉ thêm, có lệnh gỡ) | 🟡 |
| RAM available ≈2.7GB | 🟡 |
| `chatops-bot` đổi ⇒ digest Day 5 lệch (bằng chứng Day 5 = output đã lưu) | 🟡 |
| kubectl context mặc định là EKS chết ⇒ luôn `--context kind-insighthub-lab` | 🟢 |

## I. Thứ tự đóng băng
1. Xong mọi thay đổi trong `api`, `ingestion-worker`, `chatops-bot`, `security`, `tools`, `observability`, `scripts`, `tests`, `infra`, compose, `.env.example`, `AGENTS.md`, `CLAUDE.md`.
2. Cập nhật trạng thái file này **trước** bước 3 (`infra/` nằm trong digest); kết quả verify ghi ở `evidence/day6-submission.md`.
3. `python3 scripts/verify.py fingerprint`.
4. Final scan + final eval, rồi `cost` từ spend logs; dựng `eval_initial` từ dữ liệu scan đầu.
5. `evidence/day6.json` **cuối cùng**.
6. `verify-day-6.sh` (env key + `--test-timeout`), lưu output. Sửa file sau bước 3 ⇒ lặp lại từ bước 3.

## J. Thứ tự làm và trạng thái
1. Compose + LiteLLM + Postgres + 4 key + InsightHub real (reindex) — ⏳ **chặn: key upstream hết hạn**
2. Promptfoo config + generate ≥50 + initial scan — ⏳
3. Discover poisoned-doc + 3 fix + guardrail — ⏳
4. Final scan + dataset/eval converter + tests day6 + test budget/concurrency — ⏳
5. Threat model — ⏳
6. Grafana "LLM Cost" — ⏳
7. Bot summarize + coding workflow — ⏳
8. Freeze → verify → evidence → `ai-prompts/day6.md` → PR → submission — ⏳

Tổng spend hiện tại: 0.00 USD (chưa gọi LLM).
