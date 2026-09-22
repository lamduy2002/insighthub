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
- **Ước tính chi phí theo giờ** (region ap-southeast-1, chưa tính RDS/Redis —
  sẽ chốt cụ thể khi có `variables.tf` và chạy Infracost):
  - VPC, Internet Gateway, Route Table: **miễn phí**.
  - EKS control plane: **~$0.10/giờ**.
  - 1 node `t3.medium` (on-demand): **~$0.0416/giờ**.
  - ALB (do AWS Load Balancer Controller tự tạo khi Ingress được apply):
    **~$0.0225/giờ** + phụ phí LCU theo traffic.
  - **Tổng ước tính tối thiểu: ~$0.164/giờ** (chưa gồm RDS/Redis, EBS, data
    transfer — bổ sung khi Infracost breakdown chạy trên `.tf` thật).
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
