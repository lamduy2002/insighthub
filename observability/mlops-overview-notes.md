# MLOps Overview Notes (Day 4, MH12)

> **BẢN NHÁP để người học đọc và viết lại bằng lời của mình.** Spec (§8.4 MH12) chỉ ghi "4 block" mà không định nghĩa
> từng block; bản nháp chia theo Learning 5-7 (§8.3) và Self-Check 6-10 (§8.9):
> (1) bản đồ vòng đời ML, (2) bốn khái niệm cốt lõi, (3) artifact ứng dụng khác artifact model, (4) ranh giới sở hữu.
> Sửa cách chia nếu trainer hiểu khác. Mọi ví dụ "InsightHub" bám code thật của repo này.

## Block 1 - Bản đồ vòng đời ML (ML lifecycle map)

```
 dữ liệu -> chuẩn bị/feature -> huấn luyện & thử nghiệm -> đánh giá -> REGISTRY -> APPROVAL GATE
    ^                                                                                    |
    |                                                                                    v
 retrain <-- phát hiện DRIFT / chất lượng giảm <-- giám sát production <-- triển khai (canary/shadow)
                                                                                         |
                                                                              ROLLBACK khi vượt ngưỡng
```

Vòng lặp khác vòng đời phần mềm ở chỗ: **hệ thống có thể hỏng mà không đổi một dòng code nào**, vì dữ liệu ngoài đời
đổi. Do đó giám sát không dừng ở "service còn sống" (RED/USE ở Day 4) mà phải thêm chất lượng dự đoán và độ lệch dữ liệu.

## Block 2 - Bốn khái niệm cốt lõi

| Khái niệm | Là gì | Câu hỏi nó trả lời | Nối với InsightHub |
|---|---|---|---|
| **Registry** | Kho lưu phiên bản model kèm metadata (dữ liệu huấn luyện, metric đánh giá, ai/khi nào) | "Đang chạy phiên bản nào, sinh ra từ đâu, quay lại bản nào được?" | `embedding_identity_id` trong `infra/db/init.sql`: mỗi chunk gắn với danh tính embedding tạo ra nó |
| **Approval Gate** | Cổng bắt buộc giữa "train xong" và "lên production": ngưỡng metric tự động + duyệt của người | "Ai/điều kiện gì cho phép bản này phục vụ người dùng?" | Cùng tinh thần policy gate ở Day 3 (conftest/checkov) và Promptfoo ở Day 6, nhưng chấm chất lượng model thay vì cấu hình hạ tầng |
| **Drift** | Hiệu năng/đầu vào lệch khỏi lúc huấn luyện. *Data drift*: phân phối đầu vào P(X) đổi. *Concept drift*: quan hệ đầu vào-đáp án P(y\|X) đổi | "Model còn đúng với thế giới hiện tại không?" | Tài liệu người dùng upload đổi chủ đề/ngôn ngữ so với lúc chọn embedding = data drift của retrieval |
| **Rollback** | Đưa serving về phiên bản model đã được duyệt trước đó, nhanh và có thể lặp lại | "Bản mới tệ hơn thì quay lại trong bao lâu?" | Quay lại được vì registry còn bản cũ. Với InsightHub, đổi embedding cần reindex (§0.4) nên rollback không rẻ như rollback deployment |

Data drift phát hiện được **không cần nhãn** (so sánh phân phối, ví dụ PSI/KS). Concept drift thì **cần nhãn hoặc phản hồi**
(chất lượng câu trả lời, thumbs up/down) mới thấy, nên thường phát hiện chậm hơn.

## Block 3 - Artifact ứng dụng khác artifact model (4 chiều)

| Chiều | Artifact ứng dụng (image, Helm chart) | Artifact model (weights, embedding) |
|---|---|---|
| Nội dung xác định bởi | Code + dependencies | Code + **dữ liệu** + siêu tham số + seed |
| Tái lập | Build lại từ commit là ra cùng kết quả | Cần cố định cả dữ liệu và ngẫu nhiên; nhiều khi chỉ gần giống |
| Kiểm thử | Test xác định (đúng/sai) | Đánh giá thống kê (metric trên tập đánh giá, có ngưỡng) |
| Suy giảm theo thời gian | Không đổi nếu môi trường không đổi | Xuống cấp khi dữ liệu thật đổi (drift) dù không sửa gì |

Hệ quả: pipeline model cần thêm registry, approval gate theo metric và giám sát drift bên cạnh CI/CD hiện có (Day 3).

## Block 4 - Ranh giới sở hữu: DevOps và ML Engineer

| Giai đoạn | DevOps | ML Engineer |
|---|---|---|
| Thu thập / chuẩn bị dữ liệu, feature | Hỗ trợ hạ tầng lưu trữ, pipeline chạy được | **Chủ sở hữu chính** (chất lượng, nhãn, feature) |
| Huấn luyện, thử nghiệm, đánh giá | Cấp compute, GPU, quota, tái lập môi trường | **Chủ sở hữu chính** (thuật toán, siêu tham số, metric) |
| Registry | Vận hành dịch vụ, quyền truy cập, sao lưu | Quy ước phiên bản, metadata, chất lượng ghi chép |
| Approval Gate | Hiện thực gate trong CI/CD, ghi audit | Định nghĩa ngưỡng chất lượng, quyết định duyệt |
| Triển khai / serving | **Chủ sở hữu chính** (hạ tầng, scale, canary, SLO) | Yêu cầu về runtime, kiểm tra model chạy đúng |
| Giám sát hạ tầng và dịch vụ (RED/USE) | **Chủ sở hữu chính** | Dùng kết quả |
| Giám sát drift / chất lượng | Chạy nền tảng thu thập, cảnh báo, dashboard | **Chủ sở hữu chính** phần diễn giải và quyết định |
| Rollback | **Chủ sở hữu chính** phần cơ chế (nhanh, lặp lại được) | Chọn bản nào an toàn để quay lại |
| Retrain | **Không bao giờ tự làm** | **Chủ sở hữu chính** |

**Khi drift alert bắn mà team có model riêng, DevOps làm:** (1) loại trừ lỗi đường ống/đo lường trước (dữ liệu vào
bị null, đổi schema, collector hỏng), (2) thu bằng chứng có metric + timestamp giống RCA ở Day 4, (3) chuyển cho ML
Engineer kèm bằng chứng, (4) nếu chất lượng vượt ngưỡng đã thỏa thuận trong runbook thì thực hiện rollback về bản đã duyệt,
(5) **không retrain**, vì retrain đổi định nghĩa của model (dữ liệu, siêu tham số, tiêu chí đánh giá) và đó là quyết định
của người sở hữu model.
