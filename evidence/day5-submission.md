# Day 5 — Submission

Ngày nộp: 30/09/2026 · Học viên: lamduy2002 (DO2603) · Branch `day5-chatops` · PR: https://github.com/lamduy2002/insighthub/pull/4

---

## 1. Submission Format (§9.8)

```
Day 5 - Lam Duy

✓ chatops-bot/ source: https://github.com/lamduy2002/insighthub/tree/69aad68df43037aaa1093057d2cc1c4613440290/chatops-bot
   tests (verifier): https://github.com/lamduy2002/insighthub/tree/69aad68df43037aaa1093057d2cc1c4613440290/tests/milestones/day5
   RBAC identity ghi (chatops-mutator): https://github.com/lamduy2002/insighthub/blob/69aad68df43037aaa1093057d2cc1c4613440290/infra/k8s/chatops-rbac.yaml
✓ Loom screencast (3 min): https://www.loom.com/share/83dbca5f518e4834a253407e89c7e80a
✓ Audit log sample: https://github.com/lamduy2002/insighthub/blob/69aad68df43037aaa1093057d2cc1c4613440290/evidence/day5-audit.json
   (56 sự kiện thật từ chatops-bot/chatops-audit.log: 48 allowed, 4 approval_required, 4 denied; gồm lời gọi MCP Prometheus/Kubernetes)
✓ Bot live URL (if K8s deploy): không có K8s deploy (Nice-have). Bot chạy trên host qua ngrok, URL tạm nên không công khai.
✓ Slack interaction screenshot: do học viên đính kèm khi nộp (không nằm trong repo)
```

Theo §4.1:
```
✓ Verify command output: https://github.com/lamduy2002/insighthub/blob/69aad68df43037aaa1093057d2cc1c4613440290/evidence/day5-verify-output.txt  (PASS day5)
   báo cáo JSON: https://github.com/lamduy2002/insighthub/blob/69aad68df43037aaa1093057d2cc1c4613440290/evidence/day5-verify-report.json
✓ AI prompt log: https://github.com/lamduy2002/insighthub/blob/69aad68df43037aaa1093057d2cc1c4613440290/ai-prompts/day5.md
```

---

## 2. Kết quả verifier

`PATH=$PWD/venv/bin:$PATH scripts/verify-day-5.sh --namespace insighthub-local` → **PASS day5** (`scope=partial-runtime-contract`, `runtime_verified=true`, `milestone_complete=false` theo thiết kế). `source_sha256` = `8c93108d5a929eecd39dc61249a642eebaadfa9705fc3358811e21dfaf450732`; `evidence/day5.json` `mode=real`.

Verifier chỉ kiểm: file `permissions` có hàm thật, audit đã lưu hợp lệ (có cả `denied` và `approval_required`), 5 scenario bắt buộc (`test_permission_denied`, `test_approval_required`, `test_approval_bound_to_action`, `test_duplicate_event`, `test_invalid_signature`) chạy xanh với audit gắn `run_id` mới, và `GET /healthz` = 200. **Không** kiểm Slack live, MCP reuse hay identity ghi riêng: các phần đó do người chấm xem qua audit log, Loom và source.

## 3. Đã kiểm chứng ở đâu

| Nội dung | Bằng chứng |
|---|---|
| 3 intent trong Slack thật (health, ingest, pods lỗi) | `intent.*` và `mcp:prometheus.query` / `mcp:kubernetes.pods_list` trong `day5-audit.json`; Loom |
| scale → token → confirm → dry-run | `k8s.scale approval_required` rồi `k8s.scale.execute allowed` trong audit (Slack thật) |
| N ngoài 1-5 bị từ chối | `k8s.scale denied` (`replicas_out_of_range`) trong audit (Slack thật) |
| Chữ ký sai/quá 5 phút → 401 | `slack.signature denied` trong audit; `test_invalid_signature`, `test_replay_window_five_minutes` |
| Tầng destructive, user ngoài allowlist, token sai user/hết hạn/dùng lại, dedup, retry, ACK <1s khi tool chậm | **chỉ unit test** (72 pass = 36 scenario x 2 thư mục); 5 đột biến cố ý đều làm test đỏ |

## 4. Deviation so với spec

| Spec | Thực tế | Lý do |
|---|---|---|
| Redis + ARQ | SQLite WAL (`~/.local/state/insighthub-chatops/queue.db`) | Redis cluster là emptyDir + cần port-forward; DB nằm ngoài repo để không lọt vào `source_sha256` |
| Scale thực | `--dry-run=server` | Node kind 99% CPU requests; tránh làm hỏng stack Day 4 |
| Deploy K8s + K8s Secret | Bot chạy trên host + ngrok; token trong `.env` (gitignore, 600) | Nice-have; RAM 2 vCPU |
| Intent bằng LLM | Rule-based, không LLM | `LLM_PROVIDER=fixture` |
| Ingest "hôm nay" | Chênh lệch ròng của gauge `insighthub_documents_total{status="ready"}` từ 00:00 +07 | Không có counter riêng; xoá tài liệu làm số giảm (bot nói rõ) |
| `pytest chatops-bot/tests/` | Test thật ở `tests/milestones/day5/`; bản mỏng nạp lại cùng scenario | Verifier chỉ đọc thư mục milestone; source symlink bị từ chối |
| `requirements.txt` hash-pinned | Chưa tạo lại (không có `uv`); Dockerfile chưa build lại | Chỉ ảnh hưởng `docker build`; chạy local dùng venv |

Chi tiết và giới hạn đã biết: `infra/DAY5-CHECKLIST.md` §D-E.

## 5. Tái lập

```sh
# 1. Slack App (scopes app_mentions:read, chat:write; event app_mention), ngrok, chatops-bot/.env từ .env.example
cd chatops-bot && ../venv/bin/uvicorn app.main:app --port 8080     # bot
ngrok http 8080                                                     # dán https://<ngrok>/slack/events vào Slack
# 2. Kiểm tra
../venv/bin/python -m pytest -c /dev/null -q chatops-bot/tests tests/milestones/day5
PATH=$PWD/venv/bin:$PATH scripts/verify-day-5.sh --namespace insighthub-local   # bot phải đang chạy :8080
```
Cần cluster kind `insighthub-lab` (context `kind-insighthub-lab`, không phải context EKS mặc định), Prometheus ở `localhost:9090`, kubeconfig `~/.kube/insighthub-mcp-readonly.kubeconfig` và `~/.kube/insighthub-chatops-mutator.kubeconfig` (token 72h, tạo lại bằng `kubectl -n insighthub-local create token <sa> --duration=72h`). Không chạy `verify-day-4.sh` trên branch này (digest nguồn khác theo thiết kế).
