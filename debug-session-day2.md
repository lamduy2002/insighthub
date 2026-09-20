# Debug Session — Day 2: Prometheus không phản hồi

## Incident

- **Thời điểm nhận alert**: 2026-09-21, 00:08 (+07)
- **Triệu chứng**: Alert báo Prometheus không phản hồi tại `localhost:9090`. Chưa rõ nguyên nhân.

## Detection

- **Tool**: Docker MCP `list_containers(all=true)`
- **Kết quả thật**:
  ```
  b77a3572fb72  prometheus  prom/prometheus  exited  Exited (137) 2 minutes ago
  ```
- Container `prometheus` (id `b77a3572fb72`) ở trạng thái `exited`, **exit code = 137** (128 + 9 → tín hiệu SIGKILL).

## Investigation

- **Tool**: Docker MCP `container_logs(id=b77a3572fb72, tail=50)`
- **Log cuối cùng ghi nhận được** (UTC):
  ```
  time=2026-09-20T16:02:39.585Z level=INFO msg="Server is ready to receive web requests."
  time=2026-09-20T16:02:39.585Z level=INFO msg="Starting rule manager..." component="rule manager"
  ```
  Đây là dòng log cuối cùng trước khi container dừng — không có message shutdown, error, panic hay OOM nào được Prometheus tự ghi trước đó.

## Root Cause Analysis

- Bằng chứng thật thu được: exit code 137 (SIGKILL) + log ứng dụng dừng đột ngột ngay sau bước khởi động bình thường ("Starting rule manager..."), không có log lỗi/panic từ chính Prometheus.
- **Kết luận**: Log không đủ để xác định nguyên nhân cụ thể (không có bằng chứng OOM-killer, không có lệnh `docker kill`/`stop` nào được ghi lại trong phạm vi log ứng dụng có thể truy cập qua Docker MCP). Chỉ biết chắc: **process bị chấm dứt bất thường bởi SIGKILL (exit code 137)**.
- Trong môi trường production thật, bước tiếp theo để xác định chính xác nguồn gửi SIGKILL sẽ là kiểm tra Docker daemon log hoặc audit log orchestrator — nằm ngoài phạm vi quyền đọc của Docker MCP hiện tại.

## Remediation

- **Tool**: Docker MCP `start_container(id=b77a3572fb72)` → kết quả: `Container b77a3572fb72 started`.
- **Verify**: `curl http://localhost:9090/-/healthy` → `HTTP_STATUS:200`.
- **Timestamp verify xong**: 2026-09-21 00:10:31 +0700 (`date -Iseconds`).

## Time to detect / resolve

- Alert nhận lúc: 00:08 (+07)
- Resolve xong (verify healthy = 200): 00:10:31 (+07)
- **Time to resolve**: ~2 phút 31 giây.
- *Lưu ý*: các bước Detection/Investigation không có timestamp wall-clock riêng biệt được tool trả về (chỉ có mốc tương đối "2 minutes ago" từ Docker); mốc chính xác duy nhất được ghi nhận là thời điểm verify remediation (00:10:31 +07).
