# ChatOps bot (Day 5)

Luồng: Slack `app_mention` → `POST /slack/events` (verify chữ ký trên raw body, replay ≤5 phút) → dedup + enqueue vào SQLite WAL → **ACK ngay** → worker xử lý (bounded retry, backoff mũ, tối đa 3 lần) → trả lời bằng `chat.postMessage`.

- 3 intent read: health, ingest count, pods lỗi. Dữ liệu qua **MCP thật** (Prometheus `prometheus-mcp`, Kubernetes `kubernetes-mcp-server --read-only`, cấu hình như `.mcp.json`).
- Permission 3 tầng (`app/permissions.py`): read tự động; write (`scale <api|worker> to N`, N 1-5) cần `confirm <token>` trong 60s, token một lần và gắn (user, action, args); destructive luôn bị từ chối. Thực thi scale bằng identity riêng `chatops-mutator` (`infra/k8s/chatops-rbac.yaml`), `--dry-run=server`.
- Queue SQLite nằm ở `~/.local/state/insighthub-chatops/queue.db` (ngoài repo; đổi bằng `CHATOPS_QUEUE_DB`).
- Audit JSONL: `chatops-bot/chatops-audit.log` (`timestamp`, `event_id`, `action`, `decision`, `user`, ...). Không ghi secret/token.
- Catalog intent: `prompts/intents.md`.

## Chạy local
```sh
cp .env.example .env   # điền SLACK_SIGNING_SECRET, SLACK_BOT_TOKEN, SLACK_BOT_USER_ID, CHATOPS_APPROVERS
cd chatops-bot && ../venv/bin/uvicorn app.main:app --port 8080
ngrok http 8080        # Request URL: https://<ngrok>/slack/events
```
## Test
`pytest chatops-bot/tests/` (chạy lại `tests/milestones/day5/`, nơi verifier tìm test thật). Không dùng Slack/MCP/cluster thật.
