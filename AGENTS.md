# AGENTS.md - Ngữ cảnh Dự án & Quy tắc cho InsightHub (DO2603)

## 1. Architecture (Kiến trúc)
- **Trạng thái hiện tại (v0)**: 3 services đồng bộ (`web` Next.js, `api` FastAPI, `postgres` pgvector).
- **Trạng thái mục tiêu (v1 - Day 1 Refactor)**: 5 services bất đồng bộ:
  - `web`: Frontend UI (Next.js).
  - `api`: Backend API (FastAPI, tiếp nhận request HTTP và trả về 202 Accepted cho API upload).
  - `postgres`: Cơ sở dữ liệu PostgreSQL kèm extension `pgvector`.
  - `redis`: Message queue broker quản lý hàng chờ background job.
  - `ingestion-worker`: Service ARQ worker đảm nhận chia nhỏ tài liệu (chunking), tạo embedding và lưu trữ vector.
- **Luồng dữ liệu**: `POST /documents` -> Đẩy Job vào Redis -> Worker lấy Job -> Chunk & Embed -> Lưu vào Postgres -> Cập nhật trạng thái tài liệu.

## 2. Conventions (Quy ước)
- **Phong cách lập trình**: Sử dụng Python 3.11+ kèm Type hints chặt chẽ (`mypy`).
- **Mô hình Bất đồng bộ**: Dùng `async`/`await` cho các thao tác I/O và truy vấn cơ sở dữ liệu.
- **Xử lý lỗi**: Bắt lỗi rõ ràng, giữ nguyên ngữ cảnh lỗi ban đầu và cập nhật trạng thái tài liệu thành `failed` khi gặp lỗi ingestion.
- **Ghi log**: Dùng Structured Logging (định dạng JSON). Tuyệt đối không log API key/secret, lỗi thô từ AI provider, hoặc dữ liệu nhạy cảm của tài liệu.
- **Tính mô-đun**: Giữ các handler trong API gọn nhẹ; toàn bộ logic xử lý ngầm đặt trong package `ingestion-worker/worker/` (gồm `settings.py` khai báo ARQ WorkerSettings, `tasks.py` chứa hàm `ingest_document`). Tái sử dụng logic chunk/embed đã có sẵn trong `api/app/services/ingestion.py`, không viết lại từ đầu.

## 3. Commands (Lệnh thao tác)
- **Khởi tạo môi trường**:
  - `docker-compose up -d --build` (Khởi chạy đủ 5 services)
  - `docker-compose ps` (Kiểm tra cả 5 container đang ở trạng thái Running)
  - `docker-compose logs -f ingestion-worker` (Theo dõi log của worker)
- **Kiểm thử & Xác minh**:
  - `pytest` hoặc `make test-backend` (Chạy toàn bộ unit & integration test baseline)
  - `bash scripts/verify-day-1.sh` (Chạy script kiểm tra bắt buộc cho Ngày 1)
  - `bash scripts/smoke-test.sh` (Chạy smoke test kiểm tra nhanh hệ thống)

## 4. Constraints (Ràng buộc)
- **Giới hạn tệp**: Chặn các tệp upload có dung lượng vượt quá **10MB**.
- **Cam kết hiệu năng (SLA)**:
  - `POST /documents` phải phản hồi HTTP 202 Accepted trong thời gian **< 1.0 giây**.
  - Worker phải hoàn thành quá trình ingestion ngầm và chuyển trạng thái sang `ready` trong thời gian **< 30 giây**.
- **Hợp đồng API & DB**:
  - KHÔNG tự ý sửa đổi DB Schema nếu không có file migration.
  - KHÔNG bỏ qua hoặc hạ thấp các đoạn kiểm tra (assertions) trong test.
  - Giữ nguyên hợp đồng endpoint `POST /chat` và tính năng trích dẫn nguồn (source attribution).
- **An toàn bảo mật**: Không hardcode API key hay secret trong mã nguồn, log hoặc prompt log.

## 5. Domain (Nghiệp vụ)
- **RAG Pipeline**: Upload -> Queue -> Async Worker -> Chunking -> Embedding -> Vector Store -> Semantic Search -> RAG Chat.
- **Vòng đời trạng thái tài liệu**: `pending` (đang chờ worker xử lý) -> `ready` (hoàn tất, có chunk_count > 0) hoặc `failed` (lỗi, kèm error_code). Khớp đúng contract trong GETTING_STARTED.md và infra/db/init.sql.
- **Logic Worker**: Cài đặt cơ chế retry 3 lần theo chu kỳ mũ (exponential backoff) khi gặp lỗi tạm thời từ API embedding. Không tạo trùng lặp các đoạn chunk khi retry (idempotency theo document_id + content hash, đã có sẵn logic này trong `process_document()`).

## 6. References (Tham chiếu)
- `README.md` & `GETTING_STARTED.md`: Hướng dẫn khởi tạo và thiết lập dự án ban đầu.
- `Running-Project-Specification-Student.md`: Yêu cầu kỹ thuật chi tiết cho Ngày 1 và lộ trình môn học.
- `ai-prompts/day1.md`: Nhật ký lưu trữ tối thiểu 3 prompt dạng Constraint-First 4 phần dùng trong quá trình refactor.
