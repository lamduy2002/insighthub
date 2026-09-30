# Intent catalog (rule-based parsing; `summarize` adds an LLM summary through the LiteLLM gateway)

| Intent | Ví dụ | Nguồn dữ liệu | Tier |
|---|---|---|---|
| health | "InsightHub có healthy không?", "api healthy?" | Prometheus MCP: `up`, `pg_up`, `redis_up`, `probe_success` | read |
| ingest | "Hôm nay ingest bao nhiêu doc?" | Prometheus MCP: `insighthub_documents_total{status}` | read |
| pods | "Pod nào đang lỗi?" | Kubernetes MCP (read-only): pods ns `insighthub-local` | read |
| scale | "scale api to 5" (N 1-5) | identity riêng `chatops-mutator`, `--dry-run=server` | write: cần `confirm <token>` trong 60s |
| summarize | "tóm tắt tình hình", "summarize" | Prometheus + Kubernetes (như trên) rồi LLM qua LiteLLM (key `chatops-bot`) | read; LLM chỉ tóm tắt, không có công cụ, lỗi ⇒ trả số liệu thô |
| destructive | "xoá pod api", "delete ...", "exec ..." | không hỗ trợ | destructive: luôn denied |

Quy tắc trả lời: ngắn, tiếng Việt, chỉ số liệu lấy từ tool; không đoán khi tool không trả dữ liệu.
