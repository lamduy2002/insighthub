# MLOps Overview Notes (Day 4, MH12)

Ghi chú sau bài giảng MLOps overview. Chia 4 block theo Learning 5-7 (spec §8.3).

## Block 1 - Vòng đời ML

Dữ liệu → chuẩn bị/feature → train → đánh giá → đưa vào Registry → qua Approval Gate
→ triển khai (canary) → giám sát → thấy drift thì train lại, bản mới tệ thì rollback.

Khác phần mềm thường ở chỗ: model có thể hỏng mà không ai sửa dòng code nào,
vì dữ liệu ngoài đời thay đổi. Nên chỉ giám sát "service còn sống" (RED/USE như Day 4)
là chưa đủ, phải giám sát thêm chất lượng dự đoán.

## Block 2 - 4 khái niệm cốt lõi

- **Registry**: kho lưu các phiên bản model kèm thông tin (train từ dữ liệu nào,
  điểm đánh giá bao nhiêu, ai tạo). Giống ECR cho image, nhưng dành cho model.
  Trong InsightHub, `embedding_identity_id` gắn mỗi chunk với đúng embedding model đã tạo ra nó.
- **Approval Gate**: cổng kiểm tra trước khi model lên production, gồm ngưỡng điểm
  tự động và người duyệt. Giống policy gate (checkov/conftest) ở Day 3, nhưng chấm
  chất lượng model thay vì cấu hình hạ tầng.
- **Drift**: model kém dần vì thế giới thay đổi.
  Data drift: dữ liệu đầu vào khác lúc train (vd người dùng upload tài liệu chủ đề mới).
  Concept drift: quan hệ đầu vào - đáp án thay đổi, cần phản hồi của người dùng mới phát hiện.
- **Rollback**: quay lại phiên bản model cũ đã được duyệt. Làm được nhờ Registry còn giữ bản cũ.
  Với InsightHub, đổi embedding model phải reindex toàn bộ (§0.4) nên rollback không nhanh
  như rollback một deployment.

## Block 3 - Artifact ứng dụng khác artifact model

- Image/Helm chart: build lại từ cùng commit là ra cùng kết quả, test đúng/sai rõ ràng.
- Model: phụ thuộc cả code lẫn dữ liệu và yếu tố ngẫu nhiên, khó tái lập y hệt,
  kiểm tra bằng điểm thống kê có ngưỡng chứ không phải pass/fail.

## Block 4 - Ranh giới trách nhiệm

- **ML Engineer**: dữ liệu, train, chọn model, đánh giá chất lượng, quyết định khi nào train lại.
- **DevOps**: hạ tầng chạy model, pipeline đưa model lên, giám sát latency/lỗi/chi phí,
  cơ chế rollback, bảo mật và phân quyền.
- **Chỗ giao nhau**: Approval Gate và giám sát drift. DevOps dựng công cụ và cảnh báo,
  ML Engineer đặt ngưỡng và quyết định xử lý.
