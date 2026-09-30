# Day 5 Checklist — InsightHub ChatOps Bot (DO2603)

Checklist duy nhất cho Day 5 (spec §9). Khẳng định về verifier trích dòng `scripts/verify.py`. Chốt phạm vi 2026-09-30, hạn nộp 23:59 cùng ngày.

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

## A. Must-have (§9.4)
| # | Yêu cầu | Trạng thái |
|---|---|---|
| MH1 | `chatops-bot/` gồm app/, prompts/, tests/, Dockerfile | ⬜ |
| MH2 | FastAPI `/slack/events` | ⬜ |
| MH3 | Verify chữ ký (raw body, replay 5') | ⬜ |
| MH4 | Local + ngrok URL | ⬜ cần người dùng |
| MH5 | Slack App scopes + Request URL | ⬜ cần người dùng |
| MH6 | 3 intent | ⬜ |
| MH7 | MCP K8s + Prometheus; audit ghi lời gọi MCP | ⬜ |
| MH8 | Audit JSONL `chatops-audit.log` | ⬜ |
| MH9 | Permission tier, test scale | ⬜ |
| MH10 | pytest xanh | ⬜ |
| MH11 | Loom 3' | ⬜ cần người dùng |

## B. Acceptance (§9.5)
| # | Dòng | Trạng thái |
|---|---|---|
| 1 | tree chatops-bot: app/ prompts/ tests/ Dockerfile | ⬜ |
| 2 | uvicorn app.main:app chạy | ⬜ |
| 3 | curl sai chữ ký → 401 | ⬜ |
| 4 | @bot "api healthy?" | ⬜ Slack live |
| 5 | @bot "ingest count today?" | ⬜ Slack live |
| 6 | @bot "which pods failing?" | ⬜ Slack live |
| 7 | cat chatops-audit.log → JSON | ⬜ |
| 8 | @bot "scale api to 5" → confirm + token | ⬜ |
| 9 | pytest chatops-bot/tests/ pass | ⬜ |
| 10 | Loom URL | ⬜ người dùng |

## C. Non-functional (§9.3)
| # | Yêu cầu | Trạng thái |
|---|---|---|
| 1 | ACK <3s; queue bền + dedup + retry bounded | ⬜ |
| 2 | SA K8s read-only riêng | ✅ `mcp-readonly` (Day 4); kubeconfig `~/.kube/insighthub-mcp-readonly.kubeconfig` |
| 3 | Token Slack không hardcode | ⬜ `chatops-bot/.env` (đã gitignore) |
| 4 | Signature từ chối >5 phút | ⬜ |
| 5 | Token trong K8s Secret | ⚪ không áp dụng (chạy host); ghi deviation |

## D. 3 intent
| Intent | Nguồn | Tool MCP |
|---|---|---|
| InsightHub healthy? | `up`, `pg_up`, `redis_up`, `probe_success` | prometheus query |
| Hôm nay ingest bao nhiêu doc? | `insighthub_documents_total{status}` | prometheus query |
| Pod nào lỗi? | pods ns `insighthub-local` (phase, Ready, restart) | K8s pods_list_in_namespace |

## E. Permission 3 tầng
- **read**: 3 intent, tự động, audit `allowed`.
- **write**: `scale <deployment> to N` (N 1-5, deployment trong allowlist) → `approval_required` + token dùng một lần, hạn 60s UTC, gắn (user, action, args, expiry); sai user/args/hết hạn → `denied`. Thực thi bằng identity riêng `chatops-mutator` (chỉ patch `deployments/scale`), `--dry-run=server`.
- **destructive**: luôn `denied` + audit. User ngoài allowlist: `denied`.

## F. Việc CẦN NGƯỜI DÙNG làm tay
1. Slack App: scopes `app_mentions:read`, `chat:write`; Events `app_mention`; Request URL `https://<ngrok>/slack/events`; cài, `/invite`; lấy Bot token + Signing Secret → `chatops-bot/.env`.
2. ngrok: cài + authtoken (ưu tiên static domain).
3. Loom 3 phút.
4. Nộp `#day5-submissions` trước 23:59.

## G. Rủi ro
| Rủi ro | Mức | Giảm nhẹ |
|---|---|---|
| ACK <3s | 🔴 | ACK sau verify + insert SQLite; worker trả lời sau; bỏ qua `X-Slack-Retry-Num` |
| Replay 5' | 🟡 | `abs(now-ts)>300` → 401; test hai phía biên |
| Bot trả lời chính nó | 🟡 | lọc `bot_id`, `subtype`, `user==bot_user_id` |
| pytest không plugin async | 🟡 | test đồng bộ |
| RAM/CPU (còn ~2.6Gi, 2 vCPU) | 🟡 | MCP persistent, không thêm pod lớn |
| kubectl mặc định trỏ EKS đã xoá | 🟡 | chỉ dùng kubeconfig readonly / context `kind-insighthub-lab` |
| `python3` 3.10 vs venv 3.11 | 🟡 | verify bằng `venv/bin/python` |
| Digest nguồn | 🟡 | `day5.json` tạo cuối, không sửa nguồn sau đó |

## H. Ước lượng
Cấu trúc+audit 30' · signature/events/queue/worker 75' · MCP+intent 75' · permission 50' · tests 60' · live Slack 45' · evidence/submission/PR 40'. Agent ~6h; người dùng ~1h.
