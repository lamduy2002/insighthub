# Day 5 Checklist — InsightHub ChatOps Bot (DO2603)

Checklist duy nhất cho Day 5 (spec §9). Khẳng định về verifier trích dòng `scripts/verify.py`. Chốt phạm vi và hoàn tất 2026-09-30, hạn nộp 23:59 cùng ngày.

## Nguồn đã đọc
Spec §0, §4, §9 · `docs/Guide_Local_AWS_Cost_DO2603.md` · `docs/lab-guides/Day5-ChatOps-Incident-Response.md` · `scripts/VERIFICATION_CONTRACT.md` · `scripts/verify.py` (`REQUIRED_TESTS` 36-42, `evidence` 310-318, `artifact` 321-332, `implemented_python` 335-349, `validate_junit` 352-364, `run_tests` 367-396, `audit_events` 665-676, `day5` 679-696) · `scripts/verify-day-5.sh` · `chatops-bot/` skeleton · `infra/DAY4-CHECKLIST.md` · `.mcp.json`.

## Quyết định phạm vi
1. Chỉ MH1-MH11; bỏ Should/Nice-have. Confirmation token 60s vẫn làm vì Acceptance dòng 8 và `test_approval_bound_to_action` đòi.
2. Queue/dedup/retry: **SQLite WAL** (không Redis/ARQ). Redis trong cluster là emptyDir, cần thêm port-forward mong manh. Ghi deviation.
3. Chữ ký tự viết (HMAC-SHA256 trên raw body) + `httpx` gọi Slack; không dùng slack-bolt.
4. MCP: client thật qua stdio, spawn đúng `kubernetes-mcp-server@0.0.67 --read-only` và `prometheus-mcp@1.1.3` như `.mcp.json`; mỗi lời gọi tool có audit event.
5. Intent rule-based, không LLM (cluster `LLM_PROVIDER=fixture`).
6. `scale api to N`, N ∈ [1,5], ngoài khoảng → `denied`. Thực thi `--dry-run=server` (node kind 99% CPU requests). Ghi deviation.
7. Bot chạy trên host (uvicorn + ngrok), không deploy K8s.
8. Test thật ở `tests/milestones/day5/`; bản mỏng ở `chatops-bot/tests/` chạy lại cùng scenario.

## Sự thật từ code verifier
- Test: `tests/milestones/day5/test_*.py`. Bắt buộc `test_permission_denied`, `test_approval_required`, `test_approval_bound_to_action`, `test_duplicate_event`, `test_invalid_signature` (transport http). Không skip/xfail.
- pytest chạy `-c /dev/null`, `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1` ⇒ không plugin async; test viết đồng bộ.
- Audit event: `event_id`, `action`, `user` text thật; `timestamp` RFC3339 có tz; `decision ∈ {allowed, denied, approval_required}`; phải có cả `denied` và `approval_required`. Observations: `{run_id, events}` với `test_run_id == INSIGHTHUB_VERIFY_RUN_ID`, ghi vào `INSIGHTHUB_VERIFY_OBSERVATIONS`.
- `GET {bot_url}/healthz` = 200 + JSON object (mặc định `localhost:8080`). Chạy verify với `--namespace insighthub-local`.
- `evidence/day5.json`: role `permissions` (file .py) và `audit` (JSON); mode `real`, tươi ≤24h; **tạo cuối cùng**.
- Không chạy `verify-day-4.sh` trên branch này: digest nguồn Day 4 sẽ lệch (bằng chứng Day 4 = output đã lưu).

## A. Must-have (§9.4) — trạng thái cuối
| # | Yêu cầu | Trạng thái |
|---|---|---|
| MH1 | `chatops-bot/` gồm app/, prompts/, tests/, Dockerfile | ✅ `app/` (settings, security, audit, permissions, store, intents, service, adapters, factory, main), `prompts/intents.md`, `tests/`, `Dockerfile` |
| MH2 | FastAPI `/slack/events` | ✅ `uvicorn app.main:app` chạy; `/healthz` 200 |
| MH3 | Verify chữ ký (raw body, replay 5') | ✅ `app/security.py`; test `test_invalid_signature`, `test_tampered_body_rejected`, `test_replay_window_five_minutes` (299s hợp lệ, 301s bị từ chối) |
| MH4 | Local + ngrok URL | ✅ ngrok 3.39.11 (cài qua apt repo có chữ ký GPG + sha256), Slack gọi được URL public |
| MH5 | Slack App scopes + Request URL | ✅ Request URL Verified; sự kiện `app_mention` đến bot (`slack.event` trong audit log) |
| MH6 | 3 intent | ✅ health, ingest, pods đều trả lời trong Slack (`intent.*` trong `chatops-audit.log`) |
| MH7 | MCP K8s + Prometheus; audit ghi lời gọi MCP | ✅ `mcp:prometheus.query` và `mcp:kubernetes.pods_list` trong audit log; client MCP stdio thật, cấu hình như `.mcp.json` |
| MH8 | Audit JSONL `chatops-audit.log` | ✅ mọi quyết định và lời gọi tool, không có secret/token |
| MH9 | Permission tier, test scale | ✅ scale → `approval_required` → `confirm` → `k8s.scale.execute` (Slack thật); N ngoài 1-5 → `denied` (Slack thật) |
| MH10 | pytest xanh | ✅ 72 pass = 36 test x 2 vị trí (`tests/milestones/day5/` và `chatops-bot/tests/`) |
| MH11 | Loom 3' | ✅ https://www.loom.com/share/83dbca5f518e4834a253407e89c7e80a |

## B. Acceptance (§9.5)
| # | Dòng | Trạng thái |
|---|---|---|
| 1 | tree chatops-bot: app/ prompts/ tests/ Dockerfile | ✅ |
| 2 | uvicorn app.main:app chạy | ✅ |
| 3 | curl sai chữ ký → 401 | ✅ (cả qua URL ngrok) |
| 4 | @bot "api healthy?" | ✅ Slack thật |
| 5 | @bot "ingest count today?" | ✅ Slack thật (ready tăng từ 00:00 +07, kèm tổng) |
| 6 | @bot "which pods failing?" | ✅ Slack thật, có pod lỗi tạm `chaos-demo-badimage` (đã xoá) |
| 7 | cat chatops-audit.log → JSON | ✅ |
| 8 | @bot "scale api to 5" → confirm + token | ✅ Slack thật; thực thi bằng dry-run |
| 9 | pytest chatops-bot/tests/ pass | ✅ |
| 10 | Loom URL | ✅ |

## C. Non-functional (§9.3)
| # | Yêu cầu | Trạng thái |
|---|---|---|
| 1 | ACK <3s; queue bền + dedup + retry bounded | ✅ ACK không chờ tool (test: <1s khi tool chậm 5s). SQLite WAL, dedup theo `event_id`, tối đa 3 lần backoff mũ. Chưa đo độ trễ ACK thật từ phía Slack |
| 2 | SA K8s read-only riêng | ✅ `mcp-readonly` cho MCP; ghi bằng SA riêng `chatops-mutator` (`infra/k8s/chatops-rbac.yaml`) |
| 3 | Token Slack không hardcode | ✅ `chatops-bot/.env` (gitignore, quyền 600) |
| 4 | Signature từ chối >5 phút | ✅ |
| 5 | Token trong K8s Secret | ⚪ không áp dụng: bot chạy trên host (xem deviation) |

## D. Deviation so với spec (đọc trước khi chấm)
| Spec | Thực tế | Lý do |
|---|---|---|
| Queue Redis + ARQ | **SQLite WAL** (`~/.local/state/insighthub-chatops/queue.db`, ngoài repo) | Redis trong cluster là emptyDir và cần thêm port-forward; SQLite bền qua restart, 0 RAM thêm. DB nằm ngoài repo để không lọt vào `source_sha256` |
| Scale thật | **`--dry-run=server`**: API server xác thực quyền và tham số, không đổi replicas | Node kind đã 99% CPU requests; scale thật có thể làm pod Pending và ảnh hưởng stack Day 4 |
| Deploy K8s / Secret | **Bot chạy trên host** (uvicorn + ngrok), không deploy K8s | Nice-have; RAM 2 vCPU đang gánh stack Day 4. Token nằm ở `.env` chứ không phải K8s Secret |
| Intent qua LLM | **Rule-based**, không LLM | Cluster chạy `LLM_PROVIDER=fixture`; intent nhận diện bằng từ khoá Việt/Anh đã bỏ dấu |
| Slack SDK | Tự viết chữ ký + `httpx` | Yêu cầu raw-body; ít phụ thuộc |
| Ingest "hôm nay" | Chênh lệch **ròng** của gauge `insighthub_documents_total{status="ready"}` từ 00:00 +07 | Không có counter riêng; xoá tài liệu làm số giảm. Bot ghi rõ điều này |
| Test ở `chatops-bot/tests/` | Test thật ở `tests/milestones/day5/`; `chatops-bot/tests/test_chatops_bot.py` nạp lại cùng scenario | Verifier chỉ đọc `tests/milestones/day5/`; verifier từ chối symlink trong nguồn |
| `requirements.txt` hash-pinned | **Chưa tạo lại** (máy không có `uv`); `requirements.in` đã thêm `httpx`, `mcp` | Chỉ ảnh hưởng `docker build`; chạy local dùng venv. Dockerfile chưa build lại và chưa kiểm |

## E. Giới hạn đã biết (không giấu)
- Tầng **destructive** và người dùng **không thuộc `CHATOPS_APPROVERS`** chỉ được kiểm ở unit test; trên Slack thật mới có bằng chứng `denied` cho "N ngoài 1-5".
- Approval token nằm trong RAM: restart bot trong 60s làm token mất (an toàn hơn, nhưng người dùng phải xin lại).
- Retry khi MCP lỗi được test bằng double; chưa gây lỗi MCP thật.
- URL ngrok là domain do tài khoản cấp; đổi khi ngrok restart thì phải Verify lại trong Slack. Token kubeconfig `chatops-mutator` và `mcp-readonly` hết hạn ~02-03/10.
- `verify.py day5` chỉ kiểm phần đã triển khai (`milestone_complete=false`); Slack live, MCP reuse, distinct mutation identity vẫn do người chấm xem xét.

## F. Cách chạy verify (không có `pytest` ở `python3` hệ thống)
```sh
# bot phải đang chạy ở :8080
PATH=$PWD/venv/bin:$PATH scripts/verify-day-5.sh --namespace insighthub-local
```
Output lưu ở `evidence/day5-verify-output.txt` (tạo **sau** khi đóng băng nguồn). Không chạy `verify-day-4.sh` trên branch này: `source_sha256` của `day4.json` sẽ lệch; bằng chứng Day 4 là output đã lưu ở branch `day4-observability`.
