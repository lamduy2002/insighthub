# SPEC.md — InsightHub Day 3: AWS Infrastructure (Terraform)

Status: DRAFT — chưa duyệt triển khai AWS thật, chưa có file .tf nào được sinh.
References: AGENTS.md §1 (Architecture) · Running-Project-Specification-Student.md §7 · docs/Guide_Local_AWS_Cost_DO2603.md · infra/README.md

Tinh thần: Spec-driven development. Spec này là nguồn sự thật duy nhất để AI sinh
Terraform module ở bước tiếp theo. Không viết .tf trước khi spec được duyệt.
Human review + policy gate (tflint/checkov/Conftest) là lớp kiểm soát bắt buộc sau khi AI sinh.

## 0. Open Questions

Đã xác nhận — 3 quyết định cuối:

- **(a) Compute**: Tự tạo EKS cluster mới bằng Terraform, không dùng cluster
  lab đã cấp sẵn.
- **(b) Network**: Tự tạo VPC mới riêng cho lab (không dùng VPC chung
  `do2602-vpc`), để tránh rủi ro ảnh hưởng/bị ảnh hưởng bởi tài nguyên của
  học viên khác đang chạy trên VPC chung.
- **(c) HTTPS/Load Balancing**: Đạt được qua AWS Load Balancer Controller +
  Kubernetes Ingress (cài bằng Helm); controller tự sinh ALB khi Ingress
  được apply — không phải Terraform resource `aws_lb` quản lý trực tiếp.

## 1. Objective (Mục tiêu)

Deploy InsightHub lên AWS cho môi trường lab/dev, gồm:
- EKS namespace `insighthub-dev`.
- RDS PostgreSQL 16 với extension `pgvector`.
- ElastiCache Redis 7.
- IRSA (IAM Roles for Service Accounts) cho pod IAM — không dùng IAM user.

## 2. Kiến trúc dự kiến (Terraform resources)

Theo quyết định tại Mục 0: lab tự tạo VPC + EKS cluster mới hoàn toàn bằng
Terraform, không phụ thuộc VPC/cluster chung `do2602-vpc`. Kế thừa kiến trúc
target v1 tại AGENTS.md §1 (5 services: web, api, postgres, redis,
ingestion-worker) — postgres/redis chạy managed (RDS/ElastiCache), phần còn
lại (web/api/ingestion-worker) chạy trên EKS tự tạo.

### Network (Terraform tự tạo)

| Resource | Ghi chú |
|---|---|
| `aws_vpc.lab` | CIDR `10.20.0.0/16` |
| `aws_subnet.public[*]` (×2) | 2 AZ khác nhau: `ap-southeast-1a`, `ap-southeast-1b`; cả 2 đều **public** (có route tới Internet Gateway) |
| `aws_internet_gateway.lab` | Gắn vào VPC trên |
| `aws_route_table.public` + `aws_route_table_association[*]` | Route `0.0.0.0/0` → IGW; associate cả 2 subnet |

Không tạo NAT Gateway để tiết kiệm chi phí — vì cả 2 subnet đều public,
EKS node group được gán public IP để tự ra internet không cần NAT.

### Compute

| Resource | Ghi chú |
|---|---|
| `aws_eks_cluster.lab` | Dùng 2 public subnet ở trên |
| `aws_eks_node_group.lab` | 1 node, `t3.medium`, subnet gán public IP |
| `aws_iam_role.eks_cluster` | Role riêng cho EKS control plane |
| `aws_iam_role.eks_node` | Role riêng cho node group |
| `aws_iam_openid_connect_provider.eks` | OIDC provider của cluster — bắt buộc cho IRSA (MH6) |

### Database/Cache

| Resource | Ghi chú |
|---|---|
| `aws_db_instance.postgres` | PostgreSQL 16, pgvector, `storage_encrypted = true`, `publicly_accessible = false` |
| `aws_elasticache_replication_group.redis` | Redis 7 |
| `aws_db_subnet_group.lab` | Dùng 2 subnet mới tạo |
| `aws_elasticache_subnet_group.lab` | Dùng 2 subnet mới tạo |
| `aws_security_group.data` | Riêng cho RDS/Redis — ingress chỉ cho phép từ security group của EKS node group |

### Load Balancing (không phải Terraform quản lý trực tiếp)

AWS Load Balancer Controller được cài qua **Helm**, cùng bước với MH10 —
**không phải** Terraform resource. Terraform chỉ tạo phần IAM cần thiết cho
IRSA của chính controller:

| Resource | Ghi chú |
|---|---|
| `aws_iam_role.alb_controller` | Trust policy trỏ tới OIDC provider ở trên (IRSA) |
| `aws_iam_policy.alb_controller` | Policy chuẩn AWSLoadBalancerControllerIAMPolicy |

Việc cài Helm chart và tạo Kubernetes `Ingress` (dẫn tới ALB tự sinh) thuộc
phần Helm/kubectl, không nằm trong `.tf`.

### Secrets

| Resource | Ghi chú |
|---|---|
| `aws_secretsmanager_secret.db` + `aws_secretsmanager_secret_version.db` | DB credentials; pod đọc qua IRSA, không hardcode |

### Tagging

`local.common_tags` (project, environment, owner, cost_center, managed_by)
áp cho **mọi** resource Terraform tự tạo ở trên (VPC, subnet, IGW, route
table, EKS, node group, IAM role, RDS, Redis, security group, secret). Không
còn khái niệm "VPC chung không tự tag" — không áp dụng vì đã đổi hướng sang
tự tạo VPC riêng.

Cấu trúc file bắt buộc theo MH1: `infra/main.tf`, `infra/variables.tf`,
`infra/outputs.tf`, `infra/providers.tf`, `infra/backend.tf`.

## 3. Ràng buộc bắt buộc (copy nguyên văn từ spec §7.3/7.4)

- RDS/Redis: encrypted, không public (publicly_accessible=false ở RDS, không gán endpoint public cho Redis); đặt trong VPC/subnet tự tạo tại Mục 2 (không có private subnet thật — bù đắp bằng Security Group chỉ cho phép ingress từ SG của EKS node group, không có rule 0.0.0.0/0 nào).
- IRSA: ServiceAccount + IAM Role, không dùng IAM user.
- Backend Terraform: S3 + `use_lockfile` (native state locking, Terraform ≥1.10) — không DynamoDB lock.
- Tag bắt buộc mọi resource: `project`, `environment`, `owner`, `cost_center`, `managed_by`.
- Secret qua AWS Secrets Manager, không hardcode.
- Pipeline dùng OIDC AWS (no long-lived keys).
- `terraform fmt`, `tflint --recursive` không warning; `checkov -d infra/` không HIGH; `conftest test ... tfplan.json` pass.
- Infracost dự toán theo region, thời gian provision/test/teardown và phụ phí; **budget theo lượt lab, không cam kết EKS+RDS+Redis dưới $50/tháng.**

## 4. Must-have requirements (MH1–MH14, nguyên văn bảng §7.4)

| # | Requirement | Verify |
|---|---|---|
| MH1 | `infra/` complete: main.tf, variables.tf, outputs.tf, providers.tf | `ls infra/` |
| MH2 | Terraform backend S3 + native state locking (use_lockfile) | `cat infra/backend.tf` |
| MH3 | EKS namespace resource | `terraform state list \| grep namespace` |
| MH4 | RDS PostgreSQL 16, encrypted, not public | Plan output |
| MH5 | ElastiCache Redis 7, private subnet | Plan output |
| MH6 | IRSA: ServiceAccount + IAM Role binding | `kubectl describe sa insighthub` |
| MH7 | `.github/workflows/iac.yml` exists | `cat file` |
| MH8 | Pipeline jobs: fmt, lint, security-scan, policy-check, plan, cost-estimate, apply | `gh workflow view` |
| MH9 | Pipeline green on PR | `gh run list` shows ✓ |
| MH10 | InsightHub Helm deploy | Deployments web/api/worker Ready; DB/cache managed kiểm tra riêng |
| MH11 | Smoke test: upload + chat | curl tests |
| MH12 | `tflint --recursive` no warnings | CI logs |
| MH13 | `checkov` no HIGH | CI logs |
| MH14 | All resources tagged | AWS describe-tags |

## 5. Non-functional (nguyên văn §7.3)

1. `tflint --recursive` no warnings.
2. `checkov -d infra/` no HIGH.
3. `conftest test ... tfplan.json` pass.
4. Tags đầy đủ: project, environment, owner, cost_center, managed_by.
5. Pipeline OIDC AWS (no long-lived keys).
6. Secret qua AWS Secrets Manager.
7. Infracost dự toán theo region, thời gian provision/test/teardown và phụ phí; budget theo lượt lab, không cam kết EKS+RDS+Redis dưới $50/tháng.

## 6. Acceptance Criteria đo được (copy nguyên văn §7.5 — 15 dòng)

- [ ] `terraform fmt -check -recursive` → no diff
- [ ] `terraform init -backend=true` → success
- [ ] `terraform validate` → success
- [ ] `tflint --recursive` → 0 errors, 0 warnings
- [ ] `checkov -d infra/` → no HIGH
- [ ] `terraform plan -out=tfplan` → deterministic
- [ ] `conftest test --policy policy/terraform tfplan.json` → pass
- [ ] `infracost breakdown --path infra/` → dự toán theo region, thời gian lab và phụ phí
- [ ] `gh run list --workflow=iac.yml` → ✓ success
- [ ] `kubectl get ns insighthub-dev` → exists
- [ ] `kubectl get pods -n insighthub-dev` → mọi workload dự kiến Ready
- [ ] `curl https://insighthub-dev.example.com/healthz` → 200 OK
- [ ] `curl -X POST .../documents -F file=@test.pdf` → 202
- [ ] `GET /documents` → "ready" within 30s
- [ ] `curl -X POST .../chat` → 200 + answer

## 7. Ngoài phạm vi (Out of scope cho lab)

- **Backup retention 7 ngày** cho RDS: đây là Nice-to-have cho production (§7.4).
  Lab dùng dữ liệu tái tạo được, không thiết lập retention policy, không tạo
  snapshot dư thừa; nếu có snapshot phát sinh phải dọn ngay sau lượt lab
  (theo Guide_Local_AWS_Cost_DO2603.md, mục "Kiểm tra tài nguyên còn sót").
- **Drift detection scheduled (nightly cron)**: Nice-to-have cho production
  (§7.4). Lab có thể chạy thử một lần để hiểu cơ chế nhưng phải tắt lịch
  ngay sau đó — không để cron tự tạo lại tài nguyên giữa các buổi.
- (Tham khảo thêm, cũng thuộc Should-have/Nice-to-have không bắt buộc: multi-
  environment workspace dev/staging, Conftest policy org-specific nâng cao,
  modular reusable submodules, Infracost PR comment, manual approval gate cho
  production — có thể làm nếu còn thời gian nhưng không phải điều kiện Pass.)

## 8. Ngân sách & vòng đời tài nguyên (Local-first)

Áp dụng nguyên tắc bắt buộc từ `docs/Guide_Local_AWS_Cost_DO2603.md`:

- **Local-first**: `terraform fmt/validate/plan`, `tflint`, `checkov`,
  `conftest` chạy và pass ở local/CI trước. Chỉ `apply` lên AWS thật khi cần
  kiểm chứng đặc tính không thể chứng minh ở local (IAM/OIDC trust thật,
  managed service RDS/ElastiCache thật, IRSA thật qua OIDC provider của EKS).
  Local PASS không được tính là "đã hoàn thành AWS".
- **Theo lượt, có thời điểm kết thúc**: tạo tài nguyên AWS theo từng lượt lab
  có `started_at`/`expires_at` rõ ràng trong `lab-manifest.json` (owner,
  class=DO2603, lab_id, account_id, region, budget_usd, resource IDs/ARNs).
  Không chạy liên tục, không để qua đêm hoặc giữa các buổi.
- **Xóa ngay sau lượt lab**: review `terraform plan -destroy`, sau đó apply
  đúng plan đó; đối chiếu inventory trước/sau (EKS, RDS/snapshot,
  ElastiCache, NAT/EIP, EBS/S3 orphan) theo checklist "Kiểm tra tài nguyên
  còn sót" của guide. Người tạo chịu trách nhiệm cleanup + evidence.
- **Dự toán chi phí**: dùng Infracost theo region/account thực tế, tính đủ
  thời gian provision + idle + test + destroy; không giả định free tier,
  không cam kết dưới $50/tháng (đúng NFR §7.3 mục 7).
- **Ước tính chi phí chính thức** (region ap-southeast-1, chạy
  `infracost breakdown --path infra/` trên `.tf` thật ngày 2026-09-22, giả
  định chạy 730h/tháng liên tục):

  | Resource | Hạng mục | Chi phí/tháng |
  |---|---|---|
  | `aws_eks_cluster.lab` | EKS control plane (730h) | $73.00 |
  | `aws_eks_node_group.lab` | Instance `t3.medium` on-demand (730h) | $38.54 |
  | `aws_eks_node_group.lab` | EBS gp2 20GB | $2.40 |
  | `aws_db_instance.postgres` | RDS Single-AZ `db.t3.micro` (730h) | $20.44 |
  | `aws_db_instance.postgres` | Storage gp2 20GB | $2.76 |
  | `aws_elasticache_replication_group.redis` | `cache.t3.micro` on-demand (730h) | $18.25 |
  | `aws_kms_key.eks` | Customer master key | $1.00 |
  | `aws_secretsmanager_secret.db` | Secret | $0.40 |
  | `aws_secretsmanager_secret.redis` | Secret | $0.40 |
  | **TỔNG** | | **$157.19/tháng** (~$0.2154/giờ) |

  32 resource được Infracost phát hiện — 7 có chi phí, 25 miễn phí (VPC,
  subnet, IAM role, route table, OIDC provider...). Con số này **chưa gồm
  ALB** (xem lưu ý riêng bên dưới) và là chi phí nếu chạy **24/7 cả tháng**
  — theo nguyên tắc "theo lượt, có thời điểm kết thúc" ở trên, chi phí thực
  tế mỗi lượt lab sẽ thấp hơn nhiều vì chỉ tính theo số giờ thực chạy.
  - **Lưu ý về vòng đời ALB**: `terraform destroy` chỉ xóa VPC/EKS/RDS/Redis
    và các resource `.tf` khác — **không** xóa được ALB, vì ALB do Helm/
    Kubernetes Ingress tạo ra ngoài phạm vi Terraform state. Phải xóa
    `Ingress`/`Service` (kubectl/helm uninstall) **trước** khi
    `terraform destroy` cluster, đúng thứ tự trong
    `docs/Guide_Local_AWS_Cost_DO2603.md`. Nếu bỏ qua bước này, ALB có thể bị
    bỏ sót và tiếp tục tính phí dù EKS đã bị xóa.
- **CI dùng OIDC AWS**, trust bound repo/ref/environment, không lưu access
  key dài hạn.

## 9. References

- `AGENTS.md` §1 Architecture (kiến trúc v1 mục tiêu 5 services).
- `Running-Project-Specification-Student.md` §7 (Day 3 - AI-Powered IaC & Pipeline).
- `docs/Guide_Local_AWS_Cost_DO2603.md` (local-first, cost, teardown).
- `infra/README.md` (phạm vi thư mục infra/ hiện có).

## 10. Accepted Risks — Checkov Findings

Chạy `checkov -d infra/` (2026-09-22) sau khi đã sửa 6 finding quan trọng
(CKV_AWS_382, CKV_AWS_38, CKV_AWS_58, CKV2_AWS_12, CKV_AWS_30, CKV_AWS_31 —
xem chi tiết cách sửa trong `main.tf`) còn lại **17 check ID** (19 dòng, vì
2 check áp dụng cho cả 2 Secrets Manager secret `db` và `redis`) chưa pass.
Đây là các finding **chấp nhận rủi ro có chủ đích cho lab**, không phải bỏ
sót — lý do cụ thể theo từng nhóm:

| Check ID | Resource | Lý do chấp nhận |
|---|---|---|
| CKV_AWS_130 | `aws_subnet.public` | Kiến trúc lab cố ý dùng subnet public, không NAT Gateway, để tiết kiệm chi phí (đã chốt tại Mục 0(b)/Mục 2). |
| CKV_AWS_39 | `aws_eks_cluster.lab` | Đã giảm thiểu tối đa bằng `public_access_cidrs` giới hạn đúng 1 IP của operator (CKV_AWS_38 đã PASS), nhưng không thể tắt hoàn toàn `endpoint_public_access` vì kiến trúc hiện tại không có private subnet/VPN/bastion để truy cập control plane — cần hạ tầng bổ sung (VPN/bastion), ngoài phạm vi Day 3. |
| CKV_AWS_37 | `aws_eks_cluster.lab` | Bật full control-plane logging phát sinh chi phí CloudWatch Logs liên tục; production-grade observability, không cần cho lab ngắn hạn theo lượt. |
| CKV_AWS_118 | `aws_db_instance.postgres` | RDS Enhanced Monitoring tăng chi phí, cần thêm IAM role riêng; không cần cho việc kiểm chứng ingestion pipeline trong lượt lab. |
| CKV_AWS_226 | `aws_db_instance.postgres` | Cố ý pin `engine_version = "16.15"` để đảm bảo reproducibility trong lượt lab; tự động minor-upgrade có thể gây gián đoạn ngoài dự kiến giữa buổi. |
| CKV_AWS_161 | `aws_db_instance.postgres` | IAM authentication cho RDS cần sửa code kết nối DB trong `api`/`ingestion-worker` (dùng IAM token thay password) — ngoài phạm vi hạ tầng Day 3, có thể làm ở refactor sau. |
| CKV_AWS_353 | `aws_db_instance.postgres` | Performance Insights tăng chi phí; production-grade observability, không cần cho lab. |
| CKV_AWS_293 | `aws_db_instance.postgres` | Deletion protection mâu thuẫn trực tiếp với yêu cầu `terraform destroy` sạch sau mỗi lượt lab (SPEC Mục 8) — bật sẽ chặn teardown tự động. |
| CKV_AWS_129 | `aws_db_instance.postgres` | Export log RDS tăng chi phí CloudWatch Logs và có rủi ro vô tình log dữ liệu nhạy cảm nếu cấu hình sai (AGENTS.md §2 cấm log dữ liệu nhạy cảm). |
| CKV_AWS_157 | `aws_db_instance.postgres` | Multi-AZ tăng gấp đôi chi phí RDS — vượt ngân sách lượt lab (SPEC Mục 8), dữ liệu lab không critical/tái tạo được. |
| CKV_AWS_191 | `aws_elasticache_replication_group.redis` | Đã có `at_rest_encryption_enabled = true` (AWS managed key) đủ cho lab; CMK riêng thêm chi phí/độ phức tạp quản lý key không cần thiết. |
| CKV_AWS_149 | `aws_secretsmanager_secret.db`, `aws_secretsmanager_secret.redis` | Default AWS managed key (`aws/secretsmanager`) đã mã hóa at-rest đủ cho secret chỉ tồn tại trong thời gian lượt lab; CMK riêng không cần thiết. |
| CKV2_AWS_11 | `aws_vpc.lab` | VPC Flow Logs tăng chi phí lưu trữ (S3/CloudWatch Logs) liên tục; production-grade auditing, ngoài phạm vi lab theo lượt (tương tự lý do bỏ drift-detection nightly ở Mục 7). |
| CKV2_AWS_30 | `aws_db_instance.postgres` | Query Logging tăng chi phí và có cùng rủi ro log dữ liệu nhạy cảm như CKV_AWS_129. |
| CKV2_AWS_60 | `aws_db_instance.postgres` | Không áp dụng thực tế: `skip_final_snapshot = true` nên lab không tạo snapshot nào để copy tag. |
| CKV2_AWS_57 | `aws_secretsmanager_secret.db`, `aws_secretsmanager_secret.redis` | Automatic rotation cần Lambda rotation riêng + wiring mạng/IAM bổ sung — ngoài phạm vi Day 3; secret chỉ sống trong thời gian lượt lab rồi bị xóa (`recovery_window_in_days = 0`). |
| CKV2_AWS_50 | `aws_elasticache_replication_group.redis` | Multi-AZ automatic failover cần ≥2 cache cluster (replica), tăng gấp đôi chi phí Redis; lab cố ý dùng `num_cache_clusters = 1` (SPEC Mục 2: "không cần replica"). |

**Lưu ý về CKV_AWS_39**: đây là finding duy nhất trong 6 finding được giao ban
đầu **không đóng hoàn toàn** được — lý do đã ghi ở bảng trên. Nếu cần đóng
dứt điểm, hướng khả thi là thêm VPN (Client VPN endpoint hoặc Site-to-Site)
hoặc bastion host trong public subnet, rồi tắt hẳn `endpoint_public_access`
— đây là thay đổi kiến trúc lớn hơn phạm vi policy-gate hiện tại, cần quyết
định riêng nếu muốn triển khai.
