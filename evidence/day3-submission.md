# Day 3 — Submission & Self-Check

Ngày nộp: 29/09/2026 · Học viên: lamduy2002 (DO2603) · Branch `day3-terraform`

---

## 1. Submission Format (§7.8)

```
Day 3 - Lam Duy

✓ Terraform module: https://github.com/lamduy2002/insighthub/tree/day3-terraform/infra
✓ Pipeline run (green): https://github.com/lamduy2002/insighthub/actions/runs/36543176882
   fmt · lint · security-scan · policy-check · plan · cost-estimate ·
   verification-source = 7/7 success; apply = skipped (dung thiet ke tren PR)
✓ checkov scan report: artifact `checkov-report` (JUnit XML) cua chinh run tren.
   Local: 684 passed / 0 failed / 59 skipped, exit 0.
   Ban render dev rieng: 336 passed / 0 failed / 27 skipped, exit 0.
✓ Infracost report: job cost-estimate success trong run tren.
   Du toan: $157.19/thang (~$0.2154/gio), chi tiet trong infra/SPEC.md Muc 8.
✓ InsightHub live URL: https://insighthub-lamduy.do2603.click
  (da chay that tren EKS, da teardown - evidence/day3-teardown.txt)
✓ Smoke test screenshots (4 anh: terminal + Edge):
   - GET /healthz → 200
   - POST /documents → 202 (0.21s)
   - POST /chat → answer + sources
   - Web UI tren Edge (upload + chat)
  Output van ban: evidence/day3-smoke-https.txt
✓ verify-day-3.sh: PASS day3 (scope=partial-runtime-contract,
  runtime_verified=true), exit 0 - evidence/day3-verify-output.txt
✓ evidence/day3.json: mode REAL, source_sha256 va artifact_sha256 khop tuyet doi
  voi artifact verification-source do CI sinh
```

**Pull Request**: https://github.com/lamduy2002/insighthub/pull/2 —
`[Day 3] IaC + pipeline: Terraform core/platform, policy gates, Helm chart`

### Ghi chú trung thực

**MH9 đã đạt, nhưng không phải ngay từ đầu.** Lần chạy đầu tiên cả 8 job fail
sau 6 giây vì **GitHub Actions bị chặn ở cấp tài khoản** (thanh toán) — không
job nào được cấp runner, và `starter.yml` của giảng viên cũng fail y hệt cùng
lúc, chứng tỏ không phải lỗi workflow. Sau khi chủ repo gỡ chặn, pipeline còn
đỏ thêm 3 lần nữa vì 3 lỗi thật khác nhau mà local không phát hiện được
(chi tiết: `infra/DAY3-CHECKLIST.md` mục Q.6).

**Hạ tầng AWS lượt 2 apply từ LOCAL, không qua CI.** Lúc đó Actions còn bị
chặn, đợi thì hết giờ lab. Job `apply` đã viết và đã xác minh **skip đúng**
trên `pull_request`, nhưng chưa có lượt nào chạy `apply` thật qua
`workflow_dispatch` — muốn chứng minh phải dựng lại hạ tầng một lượt nữa.
Không sửa lại mô tả này cho đẹp: đó là điều đã thực sự xảy ra.

**Hai KMS key còn ở `PendingDeletion`** (06/10 và 23/10). `terraform destroy`
chỉ *schedule* xoá KMS key chứ không xoá ngay, và không rút ngắn được cửa sổ
sau khi đã schedule. Cái hết hạn 23/10 sót từ lượt lab 1. Đã ghi trong
`evidence/day3-lab2-manifest.json`.

---

## 2. Self-Check Questions (§7.9)

### 1. SPEC.md tôi viết có những section nào? Acceptance criteria có đo được không?

`infra/SPEC.md` có 13 mục: (0) Open Questions, (1) Objective, (2) Kiến trúc +
cấu trúc 3 root/state, (3) Ràng buộc bắt buộc, (4) Must-have MH1–MH14,
(5) Non-functional, (6) Acceptance Criteria, (7) Ngoài phạm vi, (8) Ngân sách &
vòng đời tài nguyên (gồm 8 bước teardown), (9) References, (10) Accepted Risks
Checkov + (10b) phần Helm/K8s, (11) Policy-as-code Conftest, (12) Thiết kế CI,
(13) Bố cục Helm chart.

**Đo được, và đã đo.** 15 dòng Acceptance đều là lệnh chạy được với kết quả
nhị phân, không phải mô tả định tính:

| Acceptance | Đo bằng | Kết quả thật |
|---|---|---|
| `fmt -check -recursive` | exit code | no diff |
| `validate` | exit code | 3/3 root Success |
| `tflint --recursive` | 0/0 | 0 error, 0 warning |
| `checkov -d infra/` | exit code | 687/0/56, exit 0 |
| `plan -out` deterministic | `-detailed-exitcode` sau apply | **0** (No changes) — core và platform |
| `conftest test` | exit code | 19 tests, 0 failures |
| `curl /healthz` | HTTP code | 200 |
| `curl -X POST /documents` | HTTP code + thời gian | 202 trong **0.21s** (SLA <1.0s) |
| `GET /documents` → ready | thời gian | **1.7s** (SLA <30s) |
| `curl -X POST /chat` | HTTP code + body | 200, có `answer` + `sources` |
| `kubectl get ns insighthub-dev` | tồn tại | Active |
| `kubectl get pods` | Ready | 4/4 Running |

Một chỗ tự sửa: dòng "plan deterministic" từng bị tôi đánh ✅ **nhầm** khi
`public_access_cidrs` còn lấy từ `data.http.my_ip` — plan đổi theo IP mạng nên
không deterministic. Đã bỏ `data.http`, chuyển sang `var.admin_cidrs` bắt buộc
truyền. Lần này đo lại bằng `-detailed-exitcode` sau apply thật mới dám tick.

### 2. 3-Layer Defense gồm những lớp nào? Layer nào bắt loại lỗi gì?

| Lớp | Công cụ | Bắt loại lỗi gì | Không bắt được gì |
|---|---|---|---|
| 1 — Cú pháp & quy ước | `terraform fmt`, `validate`, `tflint` | Sai cú pháp HCL, tham chiếu không tồn tại, thiếu biến, attribute sai với provider, quy ước đặt tên | Mọi thứ thuộc về ngữ nghĩa bảo mật |
| 2 — Bảo mật tĩnh | `checkov` | Anti-pattern đã biết trên **mã nguồn**: bucket public, thiếu mã hoá, SG mở `0.0.0.0/0`, IAM `Resource = "*"` | Giá trị đến từ biến lúc runtime (nó không resolve được), và `validation` block |
| 3 — Chính sách tổ chức | `conftest` trên **plan JSON** | Giá trị **thật sẽ được apply**: `publicly_accessible`, `transit_encryption_enabled`, `instance_class` vượt ngân sách, đủ 5 tag, `rds.force_ssl` | Drift sau khi apply (phải dùng fresh plan) |

Chỗ ba lớp thực sự bổ khuyết nhau, không phải chạy cho đủ: `public_access_cidrs`
lấy từ `var.admin_cidrs` → checkov `CKV_AWS_38` **không resolve tĩnh được** nên
tôi phải skip kèm lý do; nhưng Conftest đọc plan JSON nên thấy **giá trị cuối
cùng** và deny nếu có `0.0.0.0/0`. Lớp 2 mù đúng chỗ lớp 3 nhìn thấy.

### 3. tflint vs checkov vs Conftest — mỗi cái cho việc gì?

- **tflint** — đúng đắn về mặt *Terraform*: cấu hình có hợp lệ với provider
  không, có biến thừa/thiếu không, tên có theo quy ước không. Không biết gì về
  bảo mật.
- **checkov** — thư viện anti-pattern **dựng sẵn** của người khác, chạy trên mã
  nguồn (và cả Helm chart, Kubernetes manifest). Mạnh ở chỗ phủ rộng miễn phí;
  yếu ở chỗ không thấy giá trị runtime và **danh sách có thể lỗi thời** — như
  `CKV_AWS_339` hardcode version EKS tới 1.35 nên báo sai với 1.36 (là
  defaultVersion của AWS).
- **Conftest** — luật **của riêng tổ chức mình**, viết bằng Rego, chạy trên plan
  JSON. Dùng cho thứ không công cụ nào biết hộ: ngân sách lớp học, bộ 5 tag bắt
  buộc, quy ước riêng. Đây là lớp duy nhất nhìn thấy giá trị thật sắp apply.

Một ràng buộc vận hành đã đo được: **`tfplan.json` không được nằm trong `infra/`
khi chạy checkov** — verify.py copy cả `infra/` rồi `checkov -d .`, checkov sẽ
quét luôn file plan và fail vì không thấy inline skip. Mọi plan ghi ra
`$PLAN_DIR` ngoài repo.

### 4. OIDC AWS trust hoạt động thế nào? Vì sao tốt hơn long-lived keys?

GitHub Actions xin một **JWT ngắn hạn** từ `token.actions.githubusercontent.com`
cho từng job (cần `permissions: id-token: write`). Job gọi
`sts:AssumeRoleWithWebIdentity` kèm JWT đó; AWS xác minh chữ ký qua OIDC provider
đã đăng ký trong account, rồi đối chiếu **claim** với `Condition` trong trust
policy của role. Đổi lại là credential tạm, hết hạn theo job.

Trust policy của tôi ràng theo `sub` xuống tận **environment**, không phải chỉ repo:

- `gh_plan`: `sub = repo:lamduy2002/insighthub:environment:infra-plan`
- `gh_apply`: `sub = repo:lamduy2002/insighthub:environment:production`
  (environment này có **required reviewer**)

Dùng `StringEquals`, **không** wildcard — `repo:owner/*` hay `...:ref:*` là lỗi
kinh điển cho phép nhánh bất kỳ (kể cả từ PR) assume role production.

Tốt hơn access key dài hạn ở bốn điểm: (1) không có bí mật nào nằm trong repo
hay GitHub Secrets để rò; (2) credential hết hạn theo job, lộ log cũng vô dụng
sau vài phút; (3) quyền ràng theo repo + environment nên rò token cũng không
dùng được từ nơi khác; (4) không phải xoay vòng key thủ công.

Bổ sung phòng thủ ở tầng workflow: PR từ fork bị guard
`head.repo.full_name == github.repository` chặn khỏi mọi job chạm AWS, và job
`apply` chặn hẳn trên `pull_request`.

### 5. Cost estimate của tôi là bao nhiêu?

`infracost breakdown --path infra/` trên `.tf` thật, region `ap-southeast-1`,
giả định chạy 730h/tháng liên tục: **$157.19/tháng ≈ $0.2154/giờ**.

| Resource | Chi phí/tháng |
|---|---|
| EKS control plane | $73.00 |
| Node `t3.medium` on-demand | $38.54 |
| EBS gp2 20GB (node) | $2.40 |
| RDS `db.t3.micro` Single-AZ | $20.44 |
| RDS storage gp2 20GB | $2.76 |
| ElastiCache `cache.t3.micro` | $18.25 |
| KMS CMK (EKS) | $1.00 |
| Secrets Manager × 2 | $0.80 |
| **Tổng** | **$157.19** |

**Chi phí thực tế lượt lab này thấp hơn nhiều** vì tính theo giờ thực chạy:
hạ tầng sống ~1.2 giờ → **≈ $0.26**. Con số $157.19 **chưa gồm ALB** (do Helm
Ingress tạo, ngoài Terraform state) — đây chính là lý do teardown phải xoá
Ingress **trước** khi destroy cluster, nếu không ALB thành mồ côi và tiếp tục
tính tiền dù EKS đã biến mất.

Không giả định free tier, không cam kết dưới $50/tháng (đúng NFR §7.3 mục 7).

### 6. Resource nào của tôi có tag không đầy đủ?

**Không có resource nào của lượt lab thiếu tag.** `local.common_tags` áp qua
`default_tags` của provider nên phủ mọi resource do provider `aws` tạo, kể cả
trong module. Tagging API xác nhận **29 ARN** mang `LabId=day3-terraform`, đủ 8
tag: `project, environment, owner, cost_center, managed_by, Class, LabId,
ExpiresAt` (`evidence/day3-mh14-tags.txt`).

Ba điểm cần nói thật:

1. **Có loại resource AWS không nhận tag** — `aws_iam_role_policy`,
   `aws_iam_role_policy_attachment`, `aws_kms_alias`, `aws_eks_access_policy_association`.
   Không phải tôi bỏ sót mà API không có trường tag. Với những thứ này,
   truy vết dựa vào tên có tiền tố `insighthub-` và việc chúng gắn với một
   resource có tag.
2. **Module bootstrap dùng tag scheme khác có chủ đích**: `LabId = "bootstrap-github-oidc"`,
   thêm `Persistent = "true"`, **không có** `ExpiresAt` — vì nó không bị xoá
   theo lượt lab. Khác biệt này là cố ý, ghi trong SPEC Mục 2 phần Tagging.
3. **`owner` viết thường, không có `Owner` viết hoa**: §7.3 đòi literal `owner`,
   Guide đòi `Owner`. Áp cả hai từng gây lỗi thật `InvalidInput: Duplicate tag
   keys found` trên IAM role vì AWS coi tag key case-insensitive. Chọn `owner`
   đáp ứng được cả hai tài liệu.

### 7. Tại sao dùng RDS managed thay vì Postgres trong cluster StatefulSet?

- **Dữ liệu không chết theo cluster.** StatefulSet + PVC gắn số phận vào node
  và cluster; `terraform destroy` hoặc node bị thay là mất. RDS có vòng đời
  riêng, backup tự động, snapshot.
- **Mã hoá và ranh giới mạng có sẵn**: `storage_encrypted`, `publicly_accessible=false`,
  `rds.force_ssl=1` bắt buộc TLS phía server. Tôi đã **kiểm chứng thật** từ pod
  trong VPC: `sslmode=disable` bị từ chối (`no pg_hba.conf entry ... no
  encryption`), `sslmode=require` vào được với TLSv1.3
  (`evidence/day3-rds-tls-proof.txt`). Làm được mức này với StatefulSet phải tự
  dựng CA, tự xoay cert, tự cấu hình `pg_hba.conf`.
- **Credential không nằm trong cluster**: password sinh bằng `random_password`,
  đi thẳng vào Secrets Manager, pod đọc qua Secrets Store CSI bằng IRSA. Với
  StatefulSet thì password thường nằm trong K8s Secret (chỉ base64, không mã hoá).
- **Vận hành không phải việc của lab**: patch minor, failover, backup — mua sẵn.

**Đánh đổi, nói sòng phẳng**: RDS + ElastiCache tốn ~$38.69/tháng trong khi
StatefulSet gần như $0 (chỉ EBS), và thêm phụ thuộc vào một vendor. Với một app
nhỏ thì EKS+RDS+ElastiCache là **quá mức cần thiết** — Guide Local/AWS Cost nói
thẳng điều đó. Lý do dùng ở đây là để **kiểm chứng đặc tính không chứng minh
được ở local**: IRSA thật qua OIDC provider của EKS, managed service thật, trust
policy thật. Nên local vẫn chạy Postgres/Redis trong cluster
(chart `insighthub-local-deps`) và chỉ lên AWS theo lượt có thời điểm kết thúc.

Ràng buộc này được làm **bất biến theo cấu trúc** chứ không dựa vào trí nhớ
người deploy: tách hẳn 2 chart, chart app **không chứa template StatefulSet
nào**, nên không có đường nào cài nhầm datastore lên EKS kể cả khi truyền sai
values.

---

## 3. Bằng chứng kèm theo (`evidence/`)

| File | Nội dung |
|---|---|
| `day3-lab2-manifest.json` | Manifest lập **trước** khi tạo, cập nhật `ended_at`/`elapsed_hours` sau teardown |
| `day3-inventory-before.txt` / `day3-inventory-after.txt` | Inventory trước/sau |
| `day3-smoke-https.txt` | Smoke HTTPS đầy đủ trên domain thật |
| `day3-kubectl.txt` | `get ns`/`pods`/`svc`/`hpa`/`ingress`, `describe sa`, add-on |
| `day3-mh3-mh6.txt` | MH3 namespace, MH6 IRSA (kèm `AWS_ROLE_ARN` thật trong pod) |
| `day3-mh14-tags.txt` | 29 ARN + đối chiếu 8 tag |
| `day3-image-digests.txt` | Digest 3 image trên ECR |
| `day3-fresh-plan.txt` | Fresh plan sau apply: **No changes** cả 2 root |
| `day3-rds-tls-proof.txt` | Chứng minh `rds.force_ssl` chặn kết nối không TLS |
| `day3-route53-record.json` | Record đã tạo (dùng lại để `DELETE` lúc teardown) |
| `day3-teardown.txt` | Nhật ký teardown 8 bước |
| `day3.json` | Envelope verifier |
