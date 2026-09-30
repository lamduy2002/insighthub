# Intent catalog (rule-based, no LLM)

| Intent | Ví dụ | Nguồn dữ liệu | Tier |
|---|---|---|---|
| health | "InsightHub có healthy không?", "api healthy?" | Prometheus MCP: `up`, `pg_up`, `redis_up`, `probe_success` | read |
| ingest | "Hôm nay ingest bao nhiêu doc?" | Prometheus MCP: `insighthub_documents_total{status}` | read |
| pods | "Pod nào đang lỗi?" | Kubernetes MCP (read-only): pods ns `insighthub-local` | read |
| scale | "scale api to 5" (N 1-5) | identity riêng `chatops-mutator`, `--dry-run=server` | write: cần `confirm <token>` trong 60s |
| destructive | "xoá pod api", "delete ...", "exec ..." | không hỗ trợ | destructive: luôn denied |

Quy tắc trả lời: ngắn, tiếng Việt, chỉ số liệu lấy từ tool; không đoán khi tool không trả dữ liệu.
