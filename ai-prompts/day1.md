# Day 1 AI Prompts

## Prompt 1 - Hoàn thiện AGENTS.md dựa trên codebase thật

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.266-267, Sonnet 5, Claude Pro subscription
**Context / Evidence**: AGENTS.md (khung 6 section có sẵn), README.md, Running-Project-Specification-Student.md, GETTING_STARTED.md, api/app/services/ingestion.py, api/app/routers/documents.py, ingestion-worker/README.md, docker-compose.yml
**Time**: 09/09/2026, buổi tối

**Prompt**:
```
Đóng vai Tech Lead, hãy đọc kỹ các file sau trong repo để hiểu kiến trúc hệ thống:
- AGENTS.md (khung 6 section đang chứa TODO)
- README.md
- Running-Project-Specification-Student.md (đặc biệt mục 5 - Day 1, phần Must-have/Constraints)
- GETTING_STARTED.md
- api/app/services/ingestion.py
- api/app/routers/documents.py
- ingestion-worker/README.md và ingestion-worker/worker/.gitkeep
- docker-compose.yml

Nhiệm vụ: Đề xuất nội dung hoàn chỉnh thay thế các phần TODO trong AGENTS.md.

Yêu cầu:
1. Giữ nguyên 6 section gốc: Architecture, Conventions, Commands, Constraints,
   Domain, References.
2. Tổng file không vượt quá 200 dòng, dùng bullet points/bảng để tối ưu.
3. Chỉ trả ra nội dung đề xuất dạng Markdown để tôi review trước, không
   sửa code.
4. Phần Constraints phải phản ánh đúng ràng buộc kỹ thuật ghi trong spec.
5. Đảm bảo tất cả dòng "TODO học viên" trong cả 6 section đều được thay
   thế bằng nội dung cụ thể, không bỏ sót section nào.
```

**Why it worked**:
- Yêu cầu "đóng vai Tech Lead" giúp agent trả lời với tư duy kiến trúc thay vì mô tả chung chung
- Cấu trúc Nhiệm vụ + Yêu cầu + Ràng buộc (Constraint-first) giúp agent tập trung đúng phạm vi
- Chặn rõ "chưa sửa code" tạo gate review trước khi ghi file thật

**What I changed**:
- Phát hiện agent tự đoán sai tên state tài liệu ("processing" thay vì "pending")
  qua đối chiếu chéo với NotebookLM và GETTING_STARTED.md, yêu cầu agent sửa
  lại đúng theo bằng chứng thật trong contract thay vì suy đoán
- Yêu cầu agent kiểm tra lại tên file worker thực tế (package `worker/`
  gồm 3 file, không phải 1 file `worker.py` như agent đề xuất ban đầu)
- Duyệt bản cuối rồi mới cho agent ghi đè AGENTS.md thật

---

## Prompt 2 - Refactor ingestion đồng bộ sang Redis + ARQ worker

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.266, Sonnet 5, Claude Pro subscription
**Context / Evidence**: AGENTS.md (đã hoàn thiện), api/app/services/ingestion.py,
api/app/routers/documents.py, ingestion-worker/worker/.gitkeep, docker-compose.yml
**Time**: 10/09/2026, buổi trưa

**Prompt**:
```
Đóng vai Senior Backend Engineer. Đọc kỹ AGENTS.md, api/app/services/ingestion.py,
api/app/routers/documents.py, và ingestion-worker/worker/.gitkeep để hiểu rõ
yêu cầu.

Nhiệm vụ: Refactor ingestion từ đồng bộ sang bất đồng bộ dùng Redis + ARQ.

Yêu cầu cụ thể:
1. Tạo ingestion-worker/worker/__init__.py, settings.py, tasks.py:
   - tasks.py chứa async def ingest_document(ctx, document_id, filename, content)
     TÁI SỬ DỤNG logic process_document() đã có sẵn, KHÔNG viết lại từ đầu.
     Bọc bằng asyncio.to_thread() để không block event loop.
   - Cập nhật đúng trạng thái tài liệu: "pending" -> "ready"/"failed".
   - Thêm retry logic: 3 lần với exponential backoff khi gặp lỗi tạm thời.
2. Tạo ingestion-worker/Dockerfile và requirements.txt.
3. Sửa api/app/routers/documents.py: enqueue job vào Redis qua ARQ, trả
   về HTTP 202 ngay lập tức.
4. Sửa docker-compose.yml: thêm service "redis" và "ingestion-worker",
   tổng cộng đủ 5 service.

Ràng buộc:
- KHÔNG đổi DB schema, KHÔNG hardcode secret.
- Giữ nguyên contract /chat, không được regression.
- Giữ nguyên logic idempotency đã có trong process_document().

Trước khi sửa code: Hãy trình bày PLAN chi tiết để tôi review và approve
trước, CHƯA thực thi ngay.
```

**Why it worked**:
- Pattern "trình bày PLAN trước" tạo gate review bắt buộc trước khi động vào code
- Chỉ định rõ "tái sử dụng, không viết lại" giúp agent tránh trùng lặp logic
- Liệt kê ràng buộc rõ ràng (không đổi schema, không regression) giúp agent tự
  kiểm tra trước khi đề xuất

**What I changed**:
- Agent tự đọc Makefile và phát hiện `make test-backend` chạy worker thật
  trong container riêng biệt, nên yêu cầu cập nhật test_integration.py cho
  đúng contract 202 mới (agent tự đề xuất, tôi duyệt sau khi xem plan)
- Chọn "Yes, manually approve edits" thay vì auto mode để tự soát từng
  file thay đổi (17 file, +292/-74 dòng)
- Sau khi agent báo hoàn thành, tôi tự chạy `docker compose up`, `curl`,
  `pytest` thật trên máy (không chỉ tin báo cáo của agent) để xác minh

---

## Prompt 3 - Review và sửa lỗi guard cho exception chưa xử lý

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.266, Sonnet 5, Claude Pro subscription
**Context / Evidence**: ingestion-worker/worker/tasks.py (sau khi refactor Prompt 2),
Must-have MH7 trong Running-Project-Specification-Student.md
**Time**: 10/09/2026, buổi chiều

**Prompt**:
```
Trong ingestion-worker/worker/tasks.py, nhánh "except Exception" hiện tại
chỉ log rồi raise lại, KHÔNG ghi status='failed' vào DB. Điều này gây lỗi
với DocumentNotFound và DocumentConflict - 2 exception này được raise
TRƯỚC đoạn code tự ghi status bên trong process_document(), nên tài liệu
sẽ bị kẹt vĩnh viễn ở trạng thái "pending", vi phạm MH7 (worker phải
chuyển ready/failed trong <30s).

Hãy thêm 1 guard riêng: bắt DocumentNotFound và DocumentConflict, ghi
UPDATE documents SET status='failed', chunk_count=0, embedding_identity_id=NULL,
error_code=<mã lỗi tương ứng> WHERE id=%s AND status='pending' (điều kiện
AND status='pending' để không đè lên trạng thái ready/failed nếu
process_document đã ghi trước đó - tránh race condition).

Sau khi sửa, cho tôi xem lại toàn bộ file.
```

**Why it worked**:
- Chỉ ra chính xác dòng lỗi và hậu quả kỹ thuật cụ thể (vi phạm MH7), không
  yêu cầu chung chung "kiểm tra lỗi"
- Yêu cầu điều kiện `WHERE status='pending'` ngay trong prompt giúp agent
  tránh race condition ngay từ đầu, không phải phát hiện sau

**What I changed**:
- Sau khi agent sửa xong, agent tự phát hiện thêm lỗ hổng tương tự với
  `SchemaMismatch` - tôi duyệt cho xử lý luôn cùng cách
- Agent tiếp tục tự phát hiện `asyncio.CancelledError` (khi ARQ hủy job do
  vượt `job_timeout`) cũng không được guard bắt vì là BaseException, không
  phải Exception - tôi duyệt xử lý luôn
- Agent đề xuất thêm 1 giới hạn kiến trúc sâu hơn (thread nền không thể bị
  kill thực sự khi dùng asyncio.to_thread) - tôi quyết định KHÔNG xử lý vì
  vượt phạm vi Day 1 và không gây mất dữ liệu thật (đã có idempotency bảo vệ)
- Phát hiện thêm lỗi thật khi tự chạy `make test-backend` (KeyError: 'mode'
  do agent gán đè biến `document` trong test cũ) - yêu cầu agent sửa lại

---

## Prompt 4 - Tạo test milestone theo đúng tên scenario bắt buộc

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.266, Sonnet 5, Claude Pro subscription
**Context / Evidence**: scripts/VERIFICATION_CONTRACT.md, output thật của
`bash scripts/verify-day-1.sh`
**Time**: 10/09/2026, buổi chiều muộn

**Prompt**:
```
Đọc kỹ scripts/VERIFICATION_CONTRACT.md, đặc biệt đoạn "Days 1, 3, 5 and 6
student test suites are at tests/milestones/dayN/test_*.py".

QUAN TRỌNG - GIỚI HẠN PHẠM VI: Chỉ làm đúng phần Day 1. KHÔNG động vào,
không tham khảo Day 2-7 dù VERIFICATION_CONTRACT.md mô tả chung tất cả
các Day trong cùng 1 file.

Tạo file tests/milestones/day1/test_async_ingestion.py bằng pytest, kiểm
tra qua HTTP thật:
1. Upload -> assert 202, status "pending", <1s.
2. Poll GET /documents tới "ready" trong 30s, assert chunk_count > 0.
3. Test idempotency qua HTTP (không có endpoint reprocess).
4. Không skip/xfail.

Trước khi code, cho tôi xem PLAN cụ thể để tôi duyệt trước.
```

**Why it worked**:
- Ràng buộc "giới hạn phạm vi" ngăn agent lan man sang nội dung Day khác dù
  đọc chung 1 file contract
- Yêu cầu PLAN trước giúp phát hiện sớm vấn đề: agent tự phát hiện môi trường
  verification chỉ có pytest+PyYAML (không có requests/httpx), nên phải tự
  dựng multipart bằng urllib.request thay vì thêm dependency ngoài ý

**What I changed**:
- Agent hỏi lại hướng xử lý test idempotency vì API không có endpoint
  reprocess công khai - tôi chọn phương án "upload cùng nội dung 2 lần độc
  lập" thay vì để agent tự thêm 1 endpoint mới ngoài phạm vi Day 1
- Sau khi chạy verify-day-1.sh lần đầu, verifier tiết lộ đúng 6 tên hàm
  test bắt buộc (test_async_upload, test_worker_ingests, test_retry_idempotent,
  test_empty_input, test_duplicate_or_invalid, test_refactor_regression) -
  với 3 tên mới không rõ nghĩa, agent dừng lại hỏi tôi từng cái thay vì tự
  suy đoán logic, tôi chọn phương án bao phủ rộng nhất cho mỗi tên (ví dụ
  test_empty_input kiểm tra cả file 0-byte lẫn file chỉ có khoảng trắng)
- Yêu cầu agent tự lặp vòng "sửa - chạy lại verify - sửa tiếp" thay vì hỏi
  từng bước nhỏ, vì gần deadline cần tiết kiệm thời gian
