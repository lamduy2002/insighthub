# Day 3 AI Prompts

Bốn prompt dưới đây là **nguyên văn** những gì tôi đã gõ trong phiên làm Day 3
(29/09/2026). Không chỉnh sửa lại cho đẹp, không chép từ prompt pack của giảng
viên — chép sao lại đúng như đã gửi, kể cả chỗ viết tắt và lỗi chính tả.

---

## Prompt 1 - Đóng 3 việc còn dở của Terraform/Helm, dừng lại khi có quyết định thiết kế

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.284, Opus 5, Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `infra/main.tf`, `infra/outputs.tf`, `infra/variables.tf`, `infra/modules/eks/`, `infra/helm/insighthub/`, `infra/helm/insighthub-local-deps/`, `infra/SPEC.md`, `infra/DAY3-CHECKLIST.md`; cluster kind `insighthub-lab` đang chạy release cũ
**Time**: 29/09/2026, ~11:30 (+07)

**Prompt**:
```
Đi tiếp bước 2 → 6, dừng lại hỏi nếu có quyết định thiết kế hoặc finding mới:

2. Core: thêm data "aws_acm_certificate" (domain "*.do2603.click", statuses ["ISSUED"], most_recent true) + output certificate_arn. Ghi vào SPEC.md: cert là tài nguyên dùng chung có sẵn, Terraform chỉ tham chiếu (không tạo, không xóa); record Route53 insighthub-lamduy.do2603.click tạo bằng CLI ở job deploy và xóa ở bước 4 teardown.
3. Chuyển tạo SA insighthub sang chart local-deps; chart app serviceAccount.create=false ở cả 2 values; bỏ hook SA (nếu có).
4. eks_version: variable (default "1.36") + version = var.eks_version trong aws_eks_cluster.
5. Chạy đủ: fmt -check, validate cả 3 root, tflint --recursive, checkov -d infra/ (exit 0), plan core ra $PLAN_DIR, conftest trên plan, pytest day3, helm lint + 3 render + assert, package-chart.sh --verify. Sau đó helm upgrade trên kind (2 chart) và smoke lại bằng curl.
6. Port-forward web/api với KUBECTL_PORT_FORWARD_WEBSOCKETS=false, dừng báo tôi để kiểm UI trên Edge. Nếu biến không còn tác dụng hoặc vẫn sập, ghi nguyên nhân vào checklist và bỏ qua (không làm NodePort) — smoke curl đã PASS, UI thật sẽ kiểm trên EKS qua ALB.
7. Cập nhật SPEC.md + DAY3-CHECKLIST.md (MH10 local, O.12/O.13), commit tách hợp lý, push.
```

**Why it worked**:
- Bước 5 liệt kê **đúng 11 lệnh kiểm chứng** thay vì nói "chạy test đi". Agent
  không có chỗ để tự chọn tập kiểm tra dễ hơn, và tôi đọc kết quả theo đúng thứ
  tự mình đã định.
- Câu "dừng lại hỏi nếu có **finding mới**" là cái đắt nhất. Pin `eks_version`
  làm checkov đẻ ra `CKV_AWS_339` — agent dừng, đưa 3 phương án kèm bằng chứng
  đọc từ chính source của checkov, thay vì tự ý thêm `--skip-check` cho xanh.
- Bước 6 viết sẵn **điều kiện thất bại và cách xử lý** ("nếu vẫn sập thì ghi lý
  do và bỏ qua, không làm NodePort"). Agent không sa đà sửa một thứ ngoài phạm vi.
- Bước 2 nói rõ ranh giới sở hữu ("chỉ tham chiếu, không tạo, không xóa") nên
  agent chọn `data` source ngay, không tạo `resource`.

**What I changed**:
- Agent hỏi về `CKV_AWS_339`, tôi chọn giữ 1.36 + inline skip thay vì hạ xuống
  1.35. Lý do: 1.36 là defaultVersion của AWS, danh sách của checkov 3.3.19 mới
  là thứ lỗi thời — không hạ chuẩn hạ tầng để chiều một tool cũ.
- Agent đề xuất giữ key `serviceAccount.create` trong values dù chart không còn
  template SA. Tôi duyệt, nhưng chỉ vì agent biến nó thành **guard** (`fail` khi
  đặt `true`) — nếu để làm key chết thì tôi đã bắt bỏ.
- Bước 6 hoá ra không phải bug: lỗi `address already in use` là do agent tự
  truyền `--address 127.0.0.1,0.0.0.0` (0.0.0.0 đã bao 127.0.0.1). Tôi bắt ghi
  đúng nguyên nhân vào checklist thay vì đổ cho `KUBECTL_PORT_FORWARD_WEBSOCKETS`.

---

## Prompt 2 - Giao toàn bộ MH1-MH14 kèm ngân sách thời gian và quyền tự chạy

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.284, Opus 5, Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `infra/SPEC.md` Mục 12 (thiết kế CI), `infra/bootstrap/github-oidc/`, `scripts/verify.py`, `scripts/package-chart.sh`, `Running-Project-Specification-Student.md` §7.4/§7.5
**Time**: 29/09/2026, ~13:35 (+07)

**Prompt** (trích phần khung; phần A/B/C chi tiết dài hơn):
```
Đang gấp, còn ~2.5 tiếng. Mục tiêu: hoàn thành ĐỦ MH1-MH14 của Day 3. Bỏ Should-have/Nice-have (staging, AI explain plan, drift detection, matrix, README+diagram). Tự chạy liên tục, chỉ dừng hỏi khi có rủi ro mất dữ liệu hoặc quyết định tôi mới chốt được.

Đầu tiên: tắt 2 port-forward, giữ kind cluster.

=== PHẦN A — PIPELINE (MH7, MH8, MH9) ===
A1. Apply bootstrap OIDC: ... Lấy ARN 2 role, set GitHub repository variables bằng gh: AWS_PLAN_ROLE_ARN, AWS_APPLY_ROLE_ARN.
A2. Viết .github/workflows/iac.yml:
- Trigger: pull_request (main), push main, workflow_dispatch.
- permissions mặc định contents: read; id-token: write chỉ ở job assume AWS.
- Guard job dùng cloud identity: if: github.event.pull_request.head.repo.full_name == github.repository.
- Job ID đúng tên MH8: fmt, lint, security-scan, policy-check, plan, cost-estimate, apply.
...
- Job verification-source (mọi trigger): ... upload artifact TÊN CHÍNH XÁC verification-source kèm .tgz.
- Pin action theo commit SHA.
...
Ràng buộc: commit + push sau mỗi phần. Nguồn source phải đóng băng trước khi chạy CI run cuối dùng cho verification-source. Báo tôi tiến độ sau mỗi phần.
```

**Why it worked**:
- Nêu **ngân sách thời gian thật** ("còn ~2.5 tiếng") đổi được hành vi: agent
  đẩy việc push image lên ECR chạy song song lúc RDS còn đang provision, thay vì
  làm tuần tự cho đủ thứ tự đẹp.
- Liệt kê tường minh cái **bỏ đi** (Should-have/Nice-have) quan trọng ngang cái
  phải làm. Không có dòng đó thì agent sẽ tự thêm drift detection, staging...
  và hết giờ.
- Định nghĩa **ngưỡng dừng** rất hẹp và cụ thể: "chỉ dừng hỏi khi có rủi ro mất
  dữ liệu hoặc quyết định tôi mới chốt được". Agent chạy liên tục hàng chục
  bước mà vẫn dừng đúng 2 lần thật sự cần.
- Ràng buộc "TÊN CHÍNH XÁC verification-source" và "Job ID đúng tên MH8" chống
  được lỗi âm thầm: verifier tìm theo chuỗi khớp tuyệt đối, đặt tên khác thì
  pipeline vẫn xanh mà chấm vẫn trượt.

**What I changed**:
- Agent định `terraform import` OIDC provider rồi apply như comment cũ trong
  code hướng dẫn. Plan cho thấy sẽ **ghi đè tag `owner=DO-NGOC-VINH` và
  `lab_expiry` của học viên khác**. Tôi bắt chuyển sang `data` source — không
  quản lý tài nguyên của người khác. Đây là thay đổi tôi thấy giá trị nhất phiên.
- Agent bị `terraform apply` chặn bởi permission classifier. Tôi xác nhận lại
  yêu cầu để agent chạy tiếp, thay vì để nó tự tìm đường vòng.
- Agent báo GitHub Actions fail toàn bộ; tôi bắt **chẩn đoán chỉ-đọc có bằng
  chứng** trước khi sửa bất cứ thứ gì (xem Prompt 3).

---

## Prompt 3 - Ép chẩn đoán có bằng chứng, cấm sửa mò

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.284, Opus 5, Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: run `36532890593` (8/8 job fail sau 6s), `.github/workflows/iac.yml`, `.github/workflows/starter.yml`, GitHub REST API (`/actions/runs/.../jobs`, `/actions/permissions`)
**Time**: 29/09/2026, ~13:50 (+07)

**Prompt**:
```
VIỆC 2 — Trong lúc chờ apply/EKS provision, chẩn đoán vì sao GitHub Actions bị chặn (CHỈ ĐỌC, không sửa gì) — repo public, billing không có cảnh báo:
1. gh api /repos/lamduy2002/insighthub -q '.private,.fork,.owner.login'
2. gh run view 36532890593 --log-failed (nguyên văn annotation)
3. gh api /repos/lamduy2002/insighthub/actions/runs/36532890593/jobs -q '.jobs[] | {name, conclusion, labels}' — runner label workflow yêu cầu là gì
4. grep runs-on trong .github/workflows/iac.yml — có job nào dùng runner lớn (ubuntu-latest-4-core...), self-hosted, macos, windows không?
5. gh api /users/lamduy2002/settings/billing/actions
Nghi vấn chính: runs-on không phải ubuntu-latest → GitHub tính phí dù repo public. Kết luận có bằng chứng, đề xuất cách sửa, hỏi tôi trước khi sửa.
```

**Why it worked**:
- Nêu **giả thuyết của mình** ra trước ("nghi vấn chính: runs-on...") rồi giao
  đúng 5 lệnh để kiểm. Agent bác bỏ được giả thuyết của tôi bằng dữ liệu
  (`labels=["ubuntu-24.04"]` là runner chuẩn, miễn phí cho repo public) thay vì
  gật theo.
- "CHỈ ĐỌC, không sửa gì" + "hỏi tôi trước khi sửa" chặn được cái bẫy tốn kém
  nhất: đổi `ubuntu-24.04` → `ubuntu-latest` cho có vẻ đã xử lý, làm mất tính
  tái lập của pipeline mà bệnh vẫn còn nguyên.
- Đánh số từng lệnh khiến kết luận tra ngược được về đúng bằng chứng nào.

**What I changed**:
- Agent tìm thêm một bằng chứng tôi không nghĩ tới và nó mới là bằng chứng
  quyết định: workflow `starter.yml` **của giảng viên**, có sẵn từ trước, cũng
  fail y hệt cùng lúc → chặn nằm ở cấp tài khoản, không phải ở file tôi viết.
- Tôi duyệt cho agent chạy `gh auth refresh -s user` để đọc số liệu billing —
  nó không tự làm vì đó là thay đổi scope token của tôi.

---

## Prompt 4 - Teardown theo đúng trình tự, kèm danh sách cấm đụng

**Host**: Claude Code
**Version / Model / Auth mode**: Claude Code v2.1.284, Opus 5, Claude Team subscription (đăng nhập claude.ai, không dùng API key)
**Context / Evidence**: `infra/SPEC.md` Mục 8, `evidence/day3-lab2-manifest.json`, `evidence/day3-route53-record.json`, `docs/Guide_Local_AWS_Cost_DO2603.md`
**Time**: 29/09/2026, ~14:55 (+07)

**Prompt**:
```
Đã chụp đủ 4 ảnh evidence. Teardown NGAY theo SPEC Mục 8:
helm uninstall app → xóa hook sót (secretproviderclass, job) → chờ ALB biến mất hẳn (poll elbv2) → xóa record Route53 insighthub-lamduy.do2603.click → gỡ 4 add-on → destroy platform → destroy core → inventory sau + cập nhật manifest (ended_at, elapsed_hours, estimated_cost, actual=null).
KHÔNG đụng ACM cert (dùng chung), KHÔNG destroy bootstrap, KHÔNG xóa S3 state bucket. Nếu bị classifier chặn thì đưa tôi lệnh chạy tay.
```

**Why it worked**:
- Trình tự viết dưới dạng chuỗi mũi tên, khớp đúng 8 bước SPEC Mục 8. Thứ tự ở
  đây không phải hình thức: gỡ ALB Controller trước khi ALB biến mất thì ALB
  thành mồ côi (vẫn tính tiền) và Ingress kẹt finalizer.
- "chờ ALB biến mất hẳn (**poll elbv2**)" ép agent kiểm bằng AWS API chứ không
  ngủ vài giây rồi cho là xong.
- **Danh sách cấm đụng viết tường minh** (`ACM cert`, `bootstrap`, `S3 state
  bucket`) — ba thứ hoặc dùng chung cả lớp, hoặc không thuộc vòng đời lượt lab.
  Đây là dòng phòng thủ tôi thấy cần nhất trong cả phiên, vì destroy là thao tác
  không hoàn tác được.
- Nói trước cách xử lý khi bị chặn ("đưa tôi lệnh chạy tay") nên không mất lượt
  hỏi đáp qua lại giữa lúc hạ tầng đang tính tiền.

**What I changed**:
- Tôi bắt agent dừng teardown để chụp bằng chứng trước — đúng yêu cầu Guide là
  nộp evidence trước/sau, chụp xong mới được xoá.
- Trong lúc chụp UI tôi upload thử 2 file thật lên endpoint, trong đó có một
  hoá đơn. Agent phát hiện `sources` của `/chat` trả về file lạ và cảnh báo
  endpoint public không xác thực. Tôi cho xoá 2 tài liệu đó bằng
  `DELETE /documents/{id}` trước khi teardown, và agent kiểm chứng lại bằng
  `/chat` để chắc chunk/embedding cũng mất chứ không chỉ mất khỏi danh sách.

---

## Ghi chú trung thực về phiên này

- Hạ tầng AWS lượt 2 **apply từ local** (IAM user `DE000215`), không qua
  GitHub Actions, vì Actions bị chặn ở cấp tài khoản (billing) đúng lúc chạy.
  Workflow `.github/workflows/iac.yml` đã viết đủ 7 job và PR đã mở; lý do ghi
  trong `evidence/day3-lab2-manifest.json` và `infra/DAY3-CHECKLIST.md`.
- Hai prompt đầu vốn là một chuỗi dài nhiều bước; ở Prompt 2 tôi chỉ chép phần
  khung và Phần A để file không quá dài — phần B/C cùng văn phong, cùng cấu
  trúc đánh số.
