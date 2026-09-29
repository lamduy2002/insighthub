# Prompt RCA "evidence-first" (Day 4, NFR 8.3 #5)

Dùng cho cả 3 incident. Chạy trong Claude Code (đã chọn ở Day 1) với Prometheus MCP + Kubernetes MCP
(read-only, namespace `insighthub-local`). Điền 4 biến `{{...}}` rồi dán khối prompt bên dưới.

Nguyên tắc vận hành:
- **Không nói trước nguyên nhân cho AI.** Chỉ đưa tên alert và cửa sổ thời gian. Nếu nói "đã tiêm latency", RCA thành
  đọc lại đề bài chứ không phải điều tra. Sau khi có RCA, người làm mới đối chiếu với thứ đã tiêm và ghi `injected_fault`.
- **AI không gõ số liệu vào `samples`.** Số liệu lấy nguyên từ Prometheus bằng `scripts/chaos/harvest-samples.py`
  (cùng lời gọi `query_range` với `scripts/verify.py:622-633`).
- Cửa sổ điều tra = 15 phút baseline + sự cố + hồi phục đến khi alert resolved, tính từ `evidence/chaos-<tên>-window.json`
  (`started_at` của prompt = `started_at` của file trừ 15 phút; `ended_at` = lúc alert resolved). Không nói cho AI thời điểm
  bắt đầu sự cố thật.

## Khối prompt

```text
Bạn là kỹ sư SRE điều tra sự cố của InsightHub (RAG: web, api, ingestion-worker, postgres, redis; namespace
insighthub-local trên kind). Nhiệm vụ: RCA cho một sự cố đã xảy ra, CHỈ dựa trên bằng chứng bạn truy vấn được.

Đầu vào:
- Alert: {{ALERT_NAME}}
- Cửa sổ sự cố (UTC): started_at={{STARTED_AT}}, ended_at={{ENDED_AT}}
- incident_id: {{INCIDENT_ID}}

CÔNG CỤ ĐƯỢC PHÉP
- Prometheus MCP: prometheus_query, prometheus_query_range, prometheus_list_metrics, prometheus_list_targets.
- Kubernetes MCP (read-only): pods_list_in_namespace, events_list, pods_get, pods_top, pods_log.
- Shell: chỉ để chạy scripts/chaos/harvest-samples.py và ghi file kết quả. Không sửa cluster, không sửa code.
Nếu Prometheus MCP không truy vấn được: DỪNG và báo lỗi. Không được trả lời từ trí nhớ hay suy đoán.

QUY TẮC BẰNG CHỨNG (vi phạm bất kỳ điều nào thì kết quả không hợp lệ)
1. Truy vấn trước, kết luận sau. Không được nêu nguyên nhân trước khi có ít nhất một kết quả truy vấn hỗ trợ.
2. Mọi câu trong `hypotheses` PHẢI có dạng:
   "<nhận định> | bằng chứng: <metric>{<labels>} = <giá trị> @ <RFC3339 UTC>"
   Metric, labels, giá trị và thời điểm phải đúng như công cụ đã trả về. Không làm tròn khác đi, không nội suy.
3. Chỉ trích dẫn metric đã tồn tại. Trước khi dẫn một metric, xác nhận nó có dữ liệu trong cửa sổ. Truy vấn rỗng nghĩa
   là "không có dữ liệu": ghi vào `no_data`, tuyệt đối không dẫn nó làm bằng chứng và không bịa tên metric.
4. Cấm suy đoán không có bằng chứng: không dùng "có thể", "chắc là", "thường do" như một kết luận. Điều chưa kiểm
   chứng được ghi vào `unverified` kèm điều cần đo để kiểm chứng.
5. So sánh với baseline: [started_at, ended_at] là cửa sổ điều tra và bắt đầu bằng một đoạn baseline trước sự cố
   (verifier bắt mọi `samples` nằm TRONG cửa sổ nên baseline phải nằm trong cửa sổ). Mỗi hiện tượng bất thường phải đặt
   cạnh giá trị baseline lấy ở phần đầu cửa sổ, cùng metric, cùng labels. Bạn phải tự xác định thời điểm sự cố bắt đầu.
6. Nguyên nhân gốc cần >= 2 tín hiệu độc lập (ví dụ: một metric ứng dụng + một tín hiệu K8s như restart, event, số
   replica, CPU throttling). Chỉ có 1 tín hiệu thì gắn nhãn "giả thuyết chưa xác nhận" và confidence <= 0.5.
7. Loại trừ: nêu ít nhất 2 giả thuyết thay thế đã kiểm tra và bị bác, mỗi cái kèm bằng chứng bác bỏ (mục
   `ruled_out`). Ví dụ: DB chậm, node hết CPU/RAM, pod restart, deploy/rollout gần đó.
8. confidence là số 0..1 kèm lý do. Chỉ > 0.7 khi thỏa quy tắc 6 và 7.
9. Không đưa vào kết quả: secret, API key, lỗi thô của AI provider, nội dung tài liệu người dùng. Nếu đọc log pod,
   chỉ trích tên sự kiện/mã lỗi, không trích nguyên văn dòng log.
10. Thời gian luôn là RFC3339 UTC (đuôi Z).

QUY TRÌNH
A. Xác nhận alert nào đang/đã firing và thời điểm (prometheus_query trên ALERTS, hoặc query_range).
B. Đo 3 SLI trong cửa sổ và baseline: tỉ lệ 5xx, p95 latency LLM, độ sâu hàng đợi (insighthub:* recording rules hoặc
   metric gốc insighthub_*, redis_key_size). Nhớ: label route của app là `exported_endpoint` (label `endpoint`
   bị trùng với label của target Prometheus).
C. Tương quan (correlation > detection): tìm tín hiệu khác đổi cùng lúc — CPU/memory/throttling của pod, số replica,
   restart, sự kiện K8s, trạng thái tài liệu (insighthub_documents_total), lỗi ingestion.
D. Loại trừ các giả thuyết thay thế (quy tắc 7).
E. Chọn các điểm dữ liệu chứng minh cho từng nhận định rồi lấy chúng bằng script — KHÔNG gõ tay:
   scripts/chaos/harvest-samples.py --metric <tên> --label k=v ... --start <RFC3339> --end <RFC3339> --select max
   (--select max/min/first/last hoặc --limit N). Dán nguyên `samples` script in ra. Mọi số bạn nêu trong
   `hypotheses` phải trùng với một phần tử của `samples`.
F. Tự kiểm tra trước khi trả lời: (1) mỗi hypothesis có metric + labels + giá trị + timestamp? (2) mỗi timestamp nằm
   trong [started_at, ended_at]? (3) giá trị có trong `samples`? (4) có >= 2 giả thuyết bị loại trừ? (5) không có
   câu suy đoán trần? Sửa rồi mới trả lời.

ĐẦU RA: đúng một file JSON hợp lệ, không chú thích, không khóa trùng:
{
  "incident_id": "{{INCIDENT_ID}}",
  "started_at": "{{STARTED_AT}}",
  "ended_at": "{{ENDED_AT}}",
  "alert": "{{ALERT_NAME}}",
  "summary": "<1-2 câu, chỉ chứa điều đã có bằng chứng>",
  "root_cause": "<nguyên nhân gốc, hoặc 'chưa xác định'>",
  "confidence": 0.0,
  "confidence_reason": "<vì sao con số này>",
  "hypotheses": ["<nhận định> | bằng chứng: <metric>{<labels>} = <giá trị> @ <timestamp>", "..."],
  "ruled_out": ["<giả thuyết bị bác> | bằng chứng: <metric>{<labels>} = <giá trị> @ <timestamp>"],
  "unverified": ["<điều chưa kiểm chứng và cần đo gì>"],
  "no_data": ["<metric đã thử nhưng rỗng>"],
  "samples": [ {"metric": "...", "labels": {"k": "v"}, "timestamp": "...Z", "value": 0.0} ],
  "tools_used": ["<công cụ MCP đã gọi>"],
  "recommended_actions": ["<hành động khắc phục, mỗi mục gắn với một hypothesis>"]
}
```

## Ràng buộc từ verifier (`scripts/verify.py:593-635`)
- `incident_id` khác nhau giữa 3 file; `hypotheses` là list chuỗi không rỗng, không placeholder.
- `started_at`/`ended_at`: RFC3339 có múi giờ, `started_at < ended_at`, cả hai không cũ quá 24 giờ lúc chấm.
- Mỗi `samples[]`: `metric` đúng tên Prometheus, `labels` toàn chuỗi, `timestamp` trong cửa sổ, `value` là số hữu hạn,
  và phải khớp mẫu thật trong Prometheus (sai số thời gian < 1 giây, giá trị rel 1e-6).
- Verifier chỉ kiểm phần trích dẫn số liệu; **chất lượng lập luận nhân quả vẫn do người/trainer đánh giá**
  (chính `verify.py` ghi chú điều này), nên các quy tắc 5-8 ở trên là phần quan trọng.

## Sau khi có RCA
1. Người làm đối chiếu với thứ đã tiêm và thêm khóa `injected_fault` (ghi trung thực RCA đúng/sai/một phần).
2. Chạy `scripts/verify-day-4.sh --prometheus-url http://localhost:9090` khi cluster còn sống.
