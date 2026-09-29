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

### Cấu trúc root & state (refactor 2026-09-25)

Terraform tách thành **3 root độc lập** (state riêng, cùng bucket
`do2603-lamduy2002-insighthub-tfstate`, S3 native lock) + 4 module nội bộ:

| Root | Thư mục | State key | Nội dung | Cần cluster sống để plan? |
|---|---|---|---|---|
| bootstrap | `infra/bootstrap/github-oidc/` | `insighthub/bootstrap/github-oidc.tfstate` | GitHub OIDC provider, role `gh_plan`/`gh_apply`, KMS key saved plan — cấp account, không destroy theo lượt | Không |
| **core** | `infra/` (giữ MH1: `main.tf`/`variables.tf`/`outputs.tf`/`providers.tf`/`backend.tf`) | `insighthub/core/terraform.tfstate` | VPC/subnet, EKS + node group + OIDC provider EKS + access entry, KMS EKS, RDS + parameter group, Redis, Secrets Manager, ECR, IAM IRSA (app + ALB controller), security group. **Không có provider kubernetes / resource `kubernetes_*`** | Không |
| **platform** | `infra/platform/` | `insighthub/platform/terraform.tfstate` | Namespace `insighthub-dev`, ServiceAccount `insighthub` + `aws-load-balancer-controller`. Đọc output core qua `terraform_remote_state` (namespace, tên SA, ARN role IRSA, endpoint/CA cluster) | **Có** — và IP máy chạy phải nằm trong `public_access_cidrs` |

Module (`infra/modules/`): `network` (VPC, subnet public/private, IGW, route
table, default SG khóa), `eks` (IAM cluster/node, KMS, cluster, node group,
OIDC provider, access entry), `data` (SG data, RDS + parameter group, Redis,
random password, Secrets Manager), `ecr`. IRSA role ở root core vì nối
output của 2 module (`eks` OIDC + `data` secret ARN).

State key core đổi từ `insighthub/day3-terraform/terraform.tfstate` sang
`insighthub/core/terraform.tfstate` (state cũ rỗng — object cũ 182 byte để
nguyên, không xóa). Không cần `moved` block vì chưa có resource nào trong
state. `terraform.tfvars.example` (giá trị giả) có ở `infra/` và
`infra/platform/`; file `.tfvars` thật bị `.gitignore` chặn.

**Thứ tự apply**: bootstrap → core → platform → Helm (ALB controller, Secrets
Store CSI Driver + AWS provider, app). **Thứ tự teardown**: Mục 8.

**Quyết định thiết kế của tôi (owner, 2026-09-25)**:
- **CI dùng GitHub-hosted runner + AWS OIDC** (không self-hosted runner,
  không access key). EKS endpoint khóa theo `var.admin_cidrs` —
  `list(string)`, không default, validation từ chối `0.0.0.0/0` và `::/0`
  (thay cho `operator_cidrs`). Job apply tạm thêm IP runner rồi khôi phục —
  thiết kế ở Mục 12.
- **Secret cho pod: Secrets Store CSI Driver + AWS provider (ASCP)** — pod
  mount secret Secrets Manager qua IRSA của SA `insighthub`, không dùng
  External Secrets Operator. Cài bằng Helm (chưa viết).
- Core nhận ARN role `gh_apply` qua biến `ci_apply_role_arn` (không đọc
  remote state bootstrap — core không phụ thuộc vòng đời bootstrap).
- Platform chỉ plan/apply trong job apply, sau khi đã tạm thêm IP runner
  (Mục 12) — `gh_plan` không có access entry EKS.
- Cài Secrets Store CSI Driver ở bước Helm, không ở Terraform platform.

### Network (Terraform tự tạo — `modules/network`)

| Resource | Ghi chú |
|---|---|
| `aws_vpc.lab` | CIDR `10.20.0.0/16` |
| `aws_subnet.public[*]` (×2) | 2 AZ khác nhau: `ap-southeast-1a`, `ap-southeast-1b`; có route tới Internet Gateway — dùng cho EKS cluster/node group |
| `aws_subnet.private[*]` (×2) | Cùng 2 AZ, CIDR riêng (`cidrsubnet(vpc_cidr, 8, idx+2)`); **không** route ra IGW/NAT — dùng cho RDS/Redis (MH5) |
| `aws_internet_gateway.lab` | Gắn vào VPC trên |
| `aws_route_table.public` + `aws_route_table_association[*]` | Route `0.0.0.0/0` → IGW; associate 2 subnet public |
| `aws_route_table.private` + `aws_route_table_association[*]` | Không route block nào (chỉ route `local` AWS tự thêm ngầm định) — associate 2 subnet private |

Không tạo NAT Gateway: EKS node group vẫn ở subnet public (gán public IP tự
ra internet); RDS/Redis chuyển sang subnet private nhưng không cần ra
internet nên route table private không cần NAT — chi phí thêm $0.

### Compute (`modules/eks`)

| Resource | Ghi chú |
|---|---|
| `aws_eks_cluster.lab` | Dùng 2 public subnet ở trên; `version = var.eks_version` (pin tường minh, xem bên dưới); `public_access_cidrs = var.admin_cidrs`; `access_config { authentication_mode = "API_AND_CONFIG_MAP", bootstrap_cluster_creator_admin_permissions = false }` |
| `aws_eks_access_entry.admin[*]` + `aws_eks_access_policy_association.admin[*]` | Cho `var.ci_apply_role_arn` (role `gh_apply`) và từng ARN trong `var.operator_principal_arns` (không hardcode, truyền qua `.tfvars`) — `AmazonEKSClusterAdminPolicy`, scope `cluster` |
| `aws_eks_node_group.lab` | 1 node, `t3.medium`, subnet gán public IP |
| `aws_iam_role.eks_cluster` | Role riêng cho EKS control plane |
| `aws_iam_role.eks_node` | Role riêng cho node group |
| `aws_iam_openid_connect_provider.eks` | OIDC provider của cluster — bắt buộc cho IRSA (MH6) |

**Pin `eks_version` (2026-09-29)**: `var.eks_version` (root core, default
`"1.36"`) truyền xuống module và gán vào `aws_eks_cluster.version`. Bỏ trống
thì AWS chọn default của thời điểm apply — default đó đổi theo thời gian nên
2 lần apply cách nhau vài tháng ra 2 version khác nhau, vi phạm yêu cầu plan
deterministic (§7.5) và làm apply lại sau teardown không tái lập được cluster
cũ. Giá trị xác nhận bằng `aws eks describe-cluster-versions --region
ap-southeast-1` (2026-09-29): 1.36 là `defaultVersion`, `STANDARD_SUPPORT`,
EOL 2027-08-02. Nâng version là thay đổi có chủ đích: đổi default của biến,
review plan (EKS nâng control plane tại chỗ, node group cần nâng theo).

`bootstrap_cluster_creator_admin_permissions = false`: người/role tạo cluster
không tự có quyền admin ngầm — nếu để `true`, khi `gh_apply` là creator thì
access entry tự sinh trùng với access entry khai tường minh
(`ResourceInUseException`). Mọi quyền cluster admin nằm trong code, review
được. Hệ quả: `operator_principal_arns` bắt buộc có ít nhất 1 ARN (validation),
nếu không operator mất quyền kubectl sau khi apply local.

### Database/Cache (`modules/data`)

| Resource | Ghi chú |
|---|---|
| `aws_db_instance.postgres` | PostgreSQL 16, pgvector, `storage_encrypted = true`, `publicly_accessible = false`, `parameter_group_name = aws_db_parameter_group.postgres.name` |
| `aws_db_parameter_group.postgres` | `name = "insighthub-postgres16"` (cố định, không `name_prefix` — để Conftest đối chiếu được lúc plan), family `postgres16`, **`rds.force_ssl = 1`** — RDS từ chối kết nối không TLS |
| `aws_elasticache_replication_group.redis` | Redis 7 |
| `aws_db_subnet_group.lab` | Dùng 2 subnet **private** (MH5) |
| `aws_elasticache_subnet_group.lab` | Dùng 2 subnet **private** (MH5) |
| `aws_security_group.data` | Riêng cho RDS/Redis — ingress chỉ cho phép từ cluster security group của EKS (output module `eks`, thay cho data source `aws_eks_cluster` cũ) |

⚠️ **TLS bắt buộc với RDS**: app (`api`, `ingestion-worker`) **phải** kết nối
với `sslmode=require` (hoặc `verify-full` + CA bundle RDS) — kết nối
plaintext sẽ bị server từ chối. Secret `db-credentials` có thêm field
`sslmode = "require"`. **Chưa kiểm tra code app** — kiểm ở bước audit app
(DSN/asyncpg `ssl=` trong `api/app` và `ingestion-worker/worker`).

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

**Chứng chỉ TLS và DNS — không do Terraform sở hữu (2026-09-29)**

| Thứ | Ai tạo | Terraform làm gì |
|---|---|---|
| ACM cert wildcard `*.do2603.click` | **Tài nguyên dùng chung có sẵn** của lớp DO2603, tạo ngoài repo này | Chỉ **tham chiếu** qua `data "aws_acm_certificate" "app"` (`domain = "*.do2603.click"`, `statuses = ["ISSUED"]`, `most_recent = true`) và xuất ra output `certificate_arn`. **Không tạo, không sửa, không xóa** — cert nằm ngoài state nên `terraform destroy` không đụng tới |
| Record Route53 `insighthub-lamduy.do2603.click` | Job deploy, bằng **AWS CLI** (`aws route53 change-resource-record-sets`, ALIAS/CNAME trỏ DNS name của ALB) | Không có resource nào. ALB do ALB Controller sinh ra sau Terraform nên DNS name chỉ biết được ở thời điểm deploy; đưa vào Terraform sẽ tạo phụ thuộc ngược core → Helm |

Hệ quả vận hành: record Route53 phải **xóa tường minh ở bước 4 của teardown**
(Mục 8) — không có gì tự dọn hộ. Cert thì ngược lại: **tuyệt đối không xóa**,
vì học viên khác trong lớp cũng dùng chung.

Hệ quả với `plan`: vì là `data` source, `terraform plan` ở core từ nay **đọc
ACM thật mỗi lần chạy** — cert bị xóa hoặc hết `ISSUED` thì plan lỗi ngay
(fail-fast, đúng mong muốn: không apply ra một Ingress không có cert).

### Secrets

| Resource | Ghi chú |
|---|---|
| `aws_secretsmanager_secret.db` + `aws_secretsmanager_secret_version.db` | DB credentials (username/password/host/port/dbname/sslmode + **`database_url`** dựng sẵn bằng `urlencode(password)` và `?sslmode=require` — app chỉ đọc `DATABASE_URL`); pod mount qua Secrets Store CSI Driver + AWS provider bằng IRSA, không hardcode |
| `aws_secretsmanager_secret.redis` + `aws_secretsmanager_secret_version.redis` | Redis auth_token (chỉ `[A-Za-z0-9-_]`, 32 ký tự) + host/port + **`redis_url`** `rediss://:<token>@<primary>:6379/0` — arq không unquote password nên token phải URL-safe (DAY3-CHECKLIST mục N.3/C2); cùng cơ chế CSI |

`SecretProviderClass` + cài driver thuộc Helm chart (chưa viết); ARN secret
lấy từ output core `db_secret_arn`/`redis_secret_arn`.

### IRSA (root core) + Kubernetes (root platform) — MH3/MH6, §2.3

| Resource | Root | Ghi chú |
|---|---|---|
| `aws_iam_role.insighthub_app` | core | Trust `system:serviceaccount:insighthub-<env>:insighthub` qua OIDC provider EKS (không phải OIDC GitHub Actions); namespace/SA lấy từ `local.app_namespace`/`local.app_service_account_name` — nguồn duy nhất |
| `aws_iam_role_policy.insighthub_app_secrets` | core | Chỉ `secretsmanager:GetSecretValue` + `DescribeSecret`, đúng 2 ARN secret db/redis — không `*` |
| `aws_iam_role.alb_controller` + `aws_iam_policy.alb_controller` | core | IRSA controller, trust `kube-system:aws-load-balancer-controller` |
| `kubernetes_namespace.app` | platform | Tên = output core `app_namespace` (`insighthub-dev`) (MH3) |
| `kubernetes_service_account.insighthub` | platform | Tên/namespace/annotation `eks.amazonaws.com/role-arn` đều từ output core (MH6) |
| `kubernetes_service_account.alb_controller` | platform | `kube-system`, annotation = output core `alb_controller_role_arn`; Helm chart controller dùng `serviceAccount.create=false` |

Output core cho platform/Helm: `aws_region`, `vpc_id`, `eks_cluster_name`,
`eks_cluster_endpoint`, `eks_cluster_certificate_authority_data`,
`app_namespace`, `app_service_account_name`, `app_irsa_role_arn`,
`alb_controller_role_arn`, `alb_controller_namespace`,
`alb_controller_service_account_name`, `certificate_arn`, `db_secret_arn`, `redis_secret_arn`,
`ecr_repository_urls`, `rds_endpoint` (sensitive), `redis_endpoint`.

Provider `kubernetes` (chỉ ở platform) dùng `exec` auth (`aws eks get-token`
mỗi lần cần) thay token tĩnh ~15 phút. **Platform chỉ `validate` được ở
local khi chưa có cluster** — `plan` cần cluster sống + IP trong
`public_access_cidrs` (Mục 12).

### Container Registry (ECR — `modules/ecr`, chuẩn bị cho MH10)

| Resource | Ghi chú |
|---|---|
| `aws_ecr_repository.app["api"]`, `["web"]`, `["ingestion-worker"]` | `image_tag_mutability = "IMMUTABLE"`, `scan_on_push = true`, `force_delete = true` (xóa sạch theo lượt lab, kể cả còn image) |

### CI/CD Bootstrap — `infra/bootstrap/github-oidc/` (module riêng, KHÔNG theo lượt lab)

GitHub Actions OIDC là resource **cấp account dùng chung cả lớp DO2603**
(AWS chỉ cho phép 1 provider/URL issuer/account) — tách khỏi state chính để
không bị `terraform destroy` theo lượt lab xóa nhầm. Backend S3 cùng bucket,
key riêng `insighthub/bootstrap/github-oidc.tfstate`.

| Resource | Ghi chú |
|---|---|
| `aws_iam_openid_connect_provider.github_actions` | `lifecycle { prevent_destroy = true }`; thumbprint tính động qua `data.tls_certificate`, không hardcode |
| `aws_iam_role.gh_plan` | Trust `sub = repo:lamduy2002/insighthub:environment:infra-plan`, `aud = sts.amazonaws.com` (`StringEquals`, không wildcard). `ReadOnlyAccess` + đọc 2 secret app + **state 2 key core/platform chỉ `GetObject`** (plan không ghi state) + file `.tflock` Get/Put/Delete (native lock) + `PutObject` chỉ vào `plans/*` kèm condition SSE-KMS đúng key `tfplan` + `kms:GenerateDataKey/Encrypt` |
| `aws_iam_role.gh_apply` | Trust `sub = repo:lamduy2002/insighthub:environment:production` (GitHub Environment có **required reviewer**), `aud = sts.amazonaws.com`. CRUD scoped theo resource type core; state 2 key Get/Put/Delete; `plans/*` chỉ Get + Delete + `kms:Decrypt`; EKS access entry (cluster + `access-entry/insighthub-lab/*`); `eks:UpdateClusterConfig` + `eks:DescribeUpdate` **chỉ trên ARN `cluster/insighthub-lab`** (tách khỏi statement wildcard); RDS parameter group (`pg:insighthub-*`); ECR push (`GetAuthorizationToken` trên `*` do API, còn lại trên `repository/insighthub/*`); `iam:PassRole` 2 role EKS. KHÔNG AdministratorAccess |
| `aws_kms_key.tfplan` + `alias/insighthub-tfplan` | CMK mã hóa saved plan; key policy: root account, `gh_plan` encrypt, `gh_apply` decrypt; rotation bật |

**Saved plan**: lưu ở `s3://do2603-lamduy2002-insighthub-tfstate/plans/`
(prefix riêng, SSE-KMS bằng `tfplan` key). Lý do mã hóa riêng: saved plan
chứa giá trị nhạy cảm dạng plaintext (`random_password` DB/Redis sau apply,
biến). **KHÔNG upload plan làm GitHub artifact** — repo public, artifact
tải được bởi bất kỳ ai. Bucket tạo tay ngoài Terraform nên không thêm bucket
policy/lifecycle; ép mã hóa bằng condition IAM của `gh_plan`.

Trước khi tạo đã chạy `aws iam list-open-id-connect-providers` xác nhận
account chưa có provider `token.actions.githubusercontent.com` nào (chỉ có
6 provider OIDC của EKS cluster học viên khác) — an toàn để tạo mới thay vì
import. Nếu học viên khác tạo song song và gặp `EntityAlreadyExists`: **không
sửa code tạo lại** — chạy `terraform import aws_iam_openid_connect_provider.github_actions
arn:aws:iam::<account_id>:oidc-provider/token.actions.githubusercontent.com`
rồi apply lại.

**Trước khi gỡ provider này ở cuối Day 3**: bắt buộc chạy `aws iam list-roles`
rồi lọc từng `AssumeRolePolicyDocument` xem còn role nào khác (của học viên
khác) đang trust ARN provider này không — chỉ gỡ khi chắc chắn không còn ai
trust. Không gỡ nếu chưa kiểm tra, vì sẽ làm gãy CI của học viên khác nếu họ
cũng dùng chung provider.

### Tagging

`local.common_tags` (project, environment, owner, cost_center, managed_by,
Class, LabId, ExpiresAt) áp cho **mọi** resource Terraform tự tạo ở trên (VPC,
subnet, IGW, route table, EKS, node group, IAM role, RDS, Redis, security
group, secret, ECR, K8s namespace/ServiceAccount). Tag `owner` dùng **chữ
thường** (không phải `Owner`) — AWS coi tag key case-insensitive nên giá trị
này đáp ứng đồng thời cả spec §7.3 (đòi `owner`) và Guide Local/AWS Cost (đòi
`Owner`); dùng cả 2 case cùng lúc từng gây lỗi thật `InvalidInput: Duplicate
tag keys found` trên IAM role. `expires_at` không còn default rỗng — bắt buộc
truyền giá trị ISO 8601 thật mỗi lần apply (`var.expires_at` không default).

Module bootstrap (`infra/bootstrap/github-oidc/`) dùng tag riêng
(`LabId = "bootstrap-github-oidc"`, thêm `Persistent = "true"`, không có
`ExpiresAt`) vì không xóa theo lượt lab — không nằm trong phạm vi tagging
theo lượt như hạ tầng chính.

Cấu trúc file bắt buộc theo MH1: `infra/main.tf`, `infra/variables.tf`,
`infra/outputs.tf`, `infra/providers.tf`, `infra/backend.tf`.

## 3. Ràng buộc bắt buộc (copy nguyên văn từ spec §7.3/7.4)

- RDS/Redis: encrypted, không public (publicly_accessible=false ở RDS, không gán endpoint public cho Redis); đặt trong 2 **private subnet** tự tạo tại Mục 2 (không route ra IGW/NAT, MH5), cộng thêm Security Group chỉ cho phép ingress từ SG của EKS node group, không có rule 0.0.0.0/0 nào.
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
- [x] `conftest test --policy policy/terraform tfplan.json` → pass (local 2026-09-25, xem Mục 11)
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
- **Add-on cluster bắt buộc trên EKS** (cài bằng Helm sau platform, trước app;
  không phải Terraform): Secrets Store CSI Driver (bật `syncSecret.enabled=true`),
  AWS provider ASCP, `metrics-server` (HPA api), AWS Load Balancer Controller
  (dùng SA `aws-load-balancer-controller` do platform tạo, `serviceAccount.create=false`).
  Tất cả phải **gỡ trước platform destroy**.
- **Hook Helm không bị `helm uninstall` xóa**: `SecretProviderClass` và migration
  Job là hook `pre-install,pre-upgrade` → Helm không theo dõi chúng như resource
  của release. Migration Job đặt `helm.sh/hook-delete-policy:
  before-hook-creation,hook-succeeded`; `SecretProviderClass` (cần tồn tại suốt
  vòng đời pod) **không** dùng `hook-succeeded` → teardown phải xóa tường minh
  (bước 2 dưới đây). Phải xóa **trước** khi gỡ CSI driver, nếu không object CRD
  còn sót sau khi driver/CRD bị gỡ.
- **Thứ tự teardown đầy đủ** (bắt buộc đúng trình tự, không đảo; Guide cấm
  `terraform state rm`/force-remove finalizer để né lỗi dependency). Mọi
  plan destroy ghi ra `$PLAN_DIR` (`/tmp/insighthub-plans` local,
  `$RUNNER_TEMP` CI), review rồi apply đúng file plan đó:
  1. `helm uninstall` release app (web/api/worker + Ingress) trong `insighthub-<env>`.
     **Giữ ALB Controller đang chạy** — chính controller xóa ALB/target group
     khi Ingress bị xóa (finalizer `ingress.k8s.aws/resources`); gỡ controller
     trước sẽ bỏ sót ALB tính phí và làm Ingress kẹt finalizer, namespace
     không xóa được.
  2. Xóa hook còn sót: `kubectl -n insighthub-<env> delete secretproviderclass,job
     -l app.kubernetes.io/instance=<release>` (Job thường đã tự xóa nhờ
     hook-delete-policy; lệnh này để chắc chắn). K8s Secret do CSI sync tự bị
     xóa khi không còn pod mount — kiểm `kubectl get secret -n insighthub-<env>`.
  3. Chờ ALB bị xóa hẳn — poll `aws elbv2 describe-load-balancers` tới khi
     không còn ALB nào gắn tag cluster này (controller cần vài phút).
  4. Xóa record Route53 `insighthub-lamduy.do2603.click` bằng AWS CLI
     (`aws route53 change-resource-record-sets --change-batch` action `DELETE`,
     giá trị record phải khớp y hệt lúc tạo). Record do job deploy tạo bằng
     CLI, **không** nằm trong Terraform state nên không có gì tự xóa.
     **Không đụng tới ACM cert `*.do2603.click`** — tài nguyên dùng chung của
     lớp, Terraform chỉ `data` tham chiếu (Mục 2, Load Balancing).
  5. Gỡ add-on cluster: `helm uninstall` AWS Load Balancer Controller,
     AWS provider ASCP, Secrets Store CSI Driver, `metrics-server`.
  6. Platform destroy (cluster còn sống, IP trong `public_access_cidrs`):
     `terraform -chdir=infra/platform plan -destroy -out="$PLAN_DIR/platform-destroy.tfplan"`
     → review → `terraform -chdir=infra/platform apply "$PLAN_DIR/platform-destroy.tfplan"`.
  7. Core destroy: `terraform -chdir=infra plan -destroy -out="$PLAN_DIR/core-destroy.tfplan"`
     → review → apply file đó (EKS, RDS, Redis, VPC, IAM, KMS, ECR, Secrets Manager).
  8. (Chỉ cuối Day 3, không phải mỗi lượt) gỡ inline policy tự cấp cho `DE000215`
     (`do2603-lamduy2002-additional-permissions`). Bootstrap không destroy theo lượt.

  Quy trình `terraform destroy -target=kubernetes_*` cũ đã **bỏ** — resource
  Kubernetes giờ nằm ở root platform riêng nên destroy theo root, không cần
  `-target`.
- **CI dùng OIDC AWS**, trust bound repo/ref/environment, không lưu access
  key dài hạn.

## 9. References

- `AGENTS.md` §1 Architecture (kiến trúc v1 mục tiêu 5 services).
- `Running-Project-Specification-Student.md` §7 (Day 3 - AI-Powered IaC & Pipeline).
- `docs/Guide_Local_AWS_Cost_DO2603.md` (local-first, cost, teardown).
- `infra/README.md` (phạm vi thư mục infra/ hiện có).
- Đối chiếu với solution Day 3 của giảng viên sau khi tự thiết kế; các điểm bổ sung sau so sánh (TLS RDS, environment cho plan/apply, lưu saved plan mã hóa) và các điểm cố ý khác (ACM + domain có sẵn thay CloudFront, 2 tầng subnet, fixture LLM) được ghi lý do tại từng mục.

## 10. Accepted Risks — Checkov Findings

Chạy `checkov -d infra/` (2026-09-22, sau khi đã sửa 6 finding quan trọng ban
đầu: CKV_AWS_382, CKV_AWS_38, CKV_AWS_58, CKV2_AWS_12, CKV_AWS_30, CKV_AWS_31)
còn lại 19 dòng chưa pass. Sau khi thêm private subnet/K8s namespace-SA/ECR/
module bootstrap OIDC (2026-09-23) phát sinh thêm 9 finding mới (28 tổng).
Trong 9 finding mới, **2 finding sửa được bằng code** thay vì chấp nhận rủi
ro (không tốn chi phí, không đổi hành vi): `copy_tags_to_snapshot = true`
trên `aws_db_instance.postgres` (đóng CKV2_AWS_60) và
`encryption_configuration { encryption_type = "KMS" }` dùng AWS managed key
`aws/ecr` trên cả 3 `aws_ecr_repository.app[*]` (đóng CKV_AWS_136 ×3, không
cần CMK riêng nên không phải sửa key policy). Còn lại **24 finding** là
**chấp nhận rủi ro có chủ đích cho lab**, không phải bỏ sót — đã chuyển
thành `#checkov:skip=<ID>:<lý do>` gắn trực tiếp tại từng resource trong
`main.tf`/`infra/bootstrap/github-oidc/main.tf` (không dùng `--soft-fail`
hay `--skip-check` toàn cục). Kết quả `checkov -d infra/`: **157 passed, 0
failed, 24 skipped, exit code 0** — lý do cụ thể theo từng nhóm (nguyên văn
cũng là nội dung trong từng comment `#checkov:skip`):

| Check ID | Resource | Lý do chấp nhận |
|---|---|---|
| CKV_AWS_130 | `aws_subnet.public` | Chỉ còn EKS node group đặt ở subnet public (cần public IP tự ra internet, không NAT Gateway để tiết kiệm chi phí). RDS/Redis đã chuyển sang 2 private subnet riêng (MH5, Mục 2) — không còn public. |
| CKV_AWS_39 | `module.eks.aws_eks_cluster.lab` | Đã giảm thiểu bằng `public_access_cidrs = var.admin_cidrs` (bắt buộc CIDR hẹp, có `validation` chặn `0.0.0.0/0`), nhưng không thể tắt hoàn toàn `endpoint_public_access` vì kiến trúc hiện tại không có VPN/bastion để truy cập control plane — cần hạ tầng bổ sung, ngoài phạm vi Day 3. |
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
| CKV2_AWS_57 | `aws_secretsmanager_secret.db`, `aws_secretsmanager_secret.redis` | Automatic rotation cần Lambda rotation riêng + wiring mạng/IAM bổ sung — ngoài phạm vi Day 3; secret chỉ sống trong thời gian lượt lab rồi bị xóa (`recovery_window_in_days = 0`). |
| CKV2_AWS_50 | `aws_elasticache_replication_group.redis` | Multi-AZ automatic failover cần ≥2 cache cluster (replica), tăng gấp đôi chi phí Redis; lab cố ý dùng `num_cache_clusters = 1` (SPEC Mục 2: "không cần replica"). |

**✅ Đã sửa bằng code (2026-09-23), không còn là accepted risk:**

| Check ID | Resource | Cách sửa |
|---|---|---|
| CKV2_AWS_60 | `aws_db_instance.postgres` | Thêm `copy_tags_to_snapshot = true` — miễn phí, không ảnh hưởng vận hành (áp dụng cho automated backup snapshot, khác `skip_final_snapshot`). |
| CKV_AWS_136 ×3 | `aws_ecr_repository.app["api"\|"web"\|"ingestion-worker"]` | Thêm `encryption_configuration { encryption_type = "KMS" }`, KHÔNG chỉ định `kms_key` → dùng AWS managed key `aws/ecr` (miễn phí, không cần sửa key policy, không ảnh hưởng quyền pull image của node role — chủ động tránh dùng `aws_kms_key.eks` vì sẽ cần cấp thêm quyền `kms:Decrypt` cho node role). |

**6 finding mới còn lại (2026-09-23), phát sinh từ EKS endpoint variable/bootstrap OIDC IAM policy — đã chuyển thành `#checkov:skip` tại resource:**

| Check ID | Resource | Lý do chấp nhận |
|---|---|---|
| CKV_AWS_38 | `module.eks.aws_eks_cluster.lab` | `public_access_cidrs` lấy từ `var.admin_cidrs` (không default, validation từ chối `0.0.0.0/0` và `::/0`) — checkov không resolve tĩnh được giá trị biến và không đọc `validation` block. **Conftest kiểm tra giá trị thật trên plan JSON** (rule deny `public_access_cidrs` chứa `0.0.0.0/0`, Mục 11), nên skip này có lớp kiểm bù. (Lịch sử: trước dùng `data.http.my_ip` — checkov PASS nhưng plan không deterministic.) |
| CKV_AWS_355 ×2 | `aws_iam_role_policy.gh_apply_network`, `gh_apply_data` (bootstrap) | EC2 (VPC/subnet/IGW/route table/SG) và phần lớn action ElastiCache/KMS không hỗ trợ Resource-level ARN cho `Create*/Delete*/Modify*` trước khi resource tồn tại — bắt buộc `Resource = "*"`, đã giới hạn đúng bộ action cần (không dùng `ec2:*`/`kms:*`). |
| CKV_AWS_290 ×2 | như trên | Cùng nguyên nhân CKV_AWS_355 — action ghi (Create/Delete/Modify) đi kèm `Resource = "*"` do giới hạn API, không phải thiếu ràng buộc chủ ý. |
| CKV_AWS_289 | `aws_iam_role_policy.gh_apply_data` (bootstrap) | `kms:PutKeyPolicy`/`kms:CreateGrant` bị coi là "permissions management" — bắt buộc do KMS API yêu cầu `Resource = "*"` cho các action này trước khi key tồn tại, đã giới hạn còn lại ở mức statement riêng theo service. |

**Finding mới 2026-09-29 — phát sinh từ việc pin `eks_version`:**

| Check ID | Resource | Lý do chấp nhận |
|---|---|---|
| CKV_AWS_339 | `module.eks.aws_eks_cluster.lab` | **Dương tính giả do tool lỗi thời.** Check so `version` với một danh sách **hardcode** trong checkov 3.3.19 (`checkov/terraform/checks/resource/aws/EKSPlatformVersion.py`, `get_expected_values()` chỉ tới `"1.35"`). `1.36` là `defaultVersion` của AWS và còn `STANDARD_SUPPORT` tới 2027-08-02 (`aws eks describe-cluster-versions`), tức **đúng tinh thần của check** (chạy version còn được hỗ trợ) nhưng vẫn FAIL. Lưu ý: trước đây check này PASS chỉ vì không khai `version` (`missing_block_result = PASSED`) — pin version tường minh an toàn hơn, không phải hạ chuẩn. Gỡ skip khi nâng checkov lên bản đã biết 1.36. |

**Lưu ý về CKV_AWS_39**: đây là finding duy nhất trong 6 finding được giao ban
đầu **không đóng hoàn toàn** được — lý do đã ghi ở bảng trên. Nếu cần đóng
dứt điểm, hướng khả thi là thêm VPN (Client VPN endpoint hoặc Site-to-Site)
hoặc bastion host trong public subnet, rồi tắt hẳn `endpoint_public_access`
— đây là thay đổi kiến trúc lớn hơn phạm vi policy-gate hiện tại, cần quyết
định riêng nếu muốn triển khai.

### 10b. Helm/Kubernetes — finding từ `infra/helm/` (2026-09-28)

Đặt 2 Helm chart trong `infra/` khiến `checkov -d infra/` bật thêm 2
framework `helm` + `kubernetes` (trước đó chỉ có `terraform`). Lần quét đầu
ra **41 finding** — 11 ở `insighthub-local-deps`, 30 ở `insighthub` (chart
app chỉ lộ ra sau khi sửa được lỗi render, xem Mục 13).

**✅ Sửa thật bằng code — không phải accepted risk:**

| Check ID | Số | Cách sửa |
|---|---|---|
| CKV_K8S_38 | 6 | `automountServiceAccountToken: false` trên cả 6 pod spec (web/api/worker/migration + postgres/redis). IRSA gắn projected token riêng qua EKS pod identity webhook, Secrets Store CSI tự xin token qua `CSIDriver.tokenRequests` → không phụ thuộc token automount mặc định. **Phải kiểm lại trên EKS ở MH10**: nếu pod api/worker không lấy được credential IRSA hoặc CSI không mount được secret thì quay lại `#checkov:skip`. |
| CKV2_K8S_6 | 2 | `NetworkPolicy` thật cho Postgres/Redis (`insighthub-local-deps/templates/networkpolicy.yaml`): chỉ pod mang `app.kubernetes.io/name: insighthub` (pod của chart app) trong **cùng namespace** được vào 5432/6379. Chỉ khai `policyTypes: [Ingress]` — để egress mở nên DNS vẫn chạy. kind (kindnet/kube-network-policies) **có** thực thi NetworkPolicy nên đây là ràng buộc thật, không phải khai báo suông. |
| CKV_K8S_15 | 3 | `values.yaml` đổi mặc định `pullPolicy: Always` (an toàn cho môi trường chưa biết). Hai môi trường thật đều ghi đè `IfNotPresent` vì tag bất biến: local nạp image bằng `kind load` (không có registry để pull), dev dùng ECR `image_tag_mutability = IMMUTABLE`. |

**Accepted risk — `checkov.io/skip<n>` gắn tại annotation của từng resource
trong template** (cùng nguyên tắc với `#checkov:skip` bên Terraform: không
`--skip-check` toàn cục, không `--soft-fail`):

| Check ID | Số | Resource | Lý do chấp nhận |
|---|---|---|---|
| CKV_K8S_21 | 16 | mọi resource của cả 2 chart | **Dương tính giả.** Checkov gọi `helm template` không kèm `-n` nên Helm render ra namespace `default`. Cài đặt thật luôn có `-n insighthub-local` (kind) hoặc `-n insighthub-dev` (EKS, namespace do Terraform root platform tạo). Không có giá trị namespace nào nằm trong chart để sửa. |
| CKV_K8S_40 | 6 | 3 Deployment app + Job migration + 2 StatefulSet | UID nướng sẵn trong image: app `1001` (`appuser`/`nextjs`), `pgvector/pgvector` và `redis` official dùng `999`. Chạy UID ≥ 10000 phải build lại image và `chown` lại filesystem — ngoài phạm vi Day 3. Rủi ro thật (trùng UID với user trên host) thấp vì node là EC2 chuyên dụng của node group. |
| CKV_K8S_43 | 3 | Deployment web/api/worker | Local nạp image bằng `kind load docker-image` nên **không có digest** để tham chiếu. Trên dev, pipeline truyền `--set image.<svc>.digest` lấy từ digest ECR sau khi push (Mục 12) — chart đã hỗ trợ sẵn qua `image.<svc>.digest`. Tag hiện tại là git short SHA trên repo `IMMUTABLE` nên vẫn bất biến. |
| CKV_K8S_35 | 3 | Deployment api/worker + Job migration | App đọc `DATABASE_URL`/`REDIS_URL` từ biến môi trường (`api/app/core/config.py`). Chuyển sang secret dạng file phải sửa code app ở cả 3 service — ngoài phạm vi Day 3. Secret vẫn đến từ K8s Secret qua `secretKeyRef`, không hardcode trong manifest. |
| CKV2_K8S_6 | 4 | 4 pod của chart app | **Giới hạn đã biết**: trên EKS, VPC CNI **chưa bật network policy agent** nên `NetworkPolicy` không được thực thi. Thêm policy không enforce là cảm giác an toàn giả, lại dễ chặn nhầm traffic ALB `target-type: ip` (ALB gọi thẳng pod IP, không qua Service). Nếu bật `enableNetworkPolicy` cho VPC CNI thì mở lại mục này. |

Kết quả sau khi xử lý — `checkov -d infra/`:
**687 passed, 0 failed, 56 skipped, exit code 0**
(`terraform` 163/0/25 · `helm` 511/0/31 · `kubernetes` 13/0/0).

Cập nhật 2026-09-29 (sau khi chạy CI thật) — `checkov -d infra/`:
**684 passed, 0 failed, 59 skipped, exit 0** (`terraform` 163/0/25 ·
`helm` 508/0/34 · `kubernetes` 13/0/0). Ba thay đổi so với lần trước:

| Thay đổi | Ảnh hưởng |
|---|---|
| CKV_AWS_339 (Mục 10) | `terraform` +1 skip |
| ServiceAccount `insighthub` chuyển sang chart `insighthub-local-deps` (Mục 13) | `helm` +1 skip — SA giờ nằm trong bản render mặc định của local-deps nên bị CKV_K8S_21 soi |
| **CKV_K8S_15 ×3** trên Deployment web/api/worker | `helm` +3 skip. `values-dev` đặt `pullPolicy: IfNotPresent` có chủ đích: deploy thật luôn truyền `image.<svc>.digest` (Mục 12) nên tham chiếu đã bất biến, kéo lại image mỗi lần restart chỉ tốn thời gian và quota ECR mà không đổi gì. Values mặc định vẫn là `Always` cho môi trường chưa biết. **Chỉ lộ ra ở bản render dev** — bản render mặc định dùng `Always` nên luôn PASS |
| **CKV_K8S_21 trên `Ingress`** | `helm` +1 skip. Annotation `checkov.io/skip` bị **quên** ở đúng resource duy nhất không xuất hiện trong bản render mặc định |

## 11. Policy-as-code — Conftest (`infra/policy/terraform/`)

Policy gate chạy trên **plan JSON thật** (`terraform show -json tfplan`), bổ
sung cho checkov (checkov đọc HCL tĩnh, Conftest đọc giá trị đã resolve).

**Phiên bản & cú pháp**: pin **Conftest 0.70.x** (đã kiểm với 0.70.1 / OPA
1.20.2). Rego viết theo cú pháp v1 (`import rego.v1`, `deny contains msg if
{...}`) — Conftest/OPA cũ (< 1.0) không parse được. **Pipeline CI (`iac.yml`)
phải cài đúng Conftest 0.70.x** (tải binary release theo version cố định,
không dùng `latest`), và runner phải có `conftest` trong `PATH` trước bước
`pytest tests/milestones/day3` (test gọi `shutil.which("conftest")`, thiếu
binary → test FAIL, không skip).

**Lệnh** (chạy từ `infra/`; `PLAN_DIR=/tmp/insighthub-plans` ở local,
`PLAN_DIR=$RUNNER_TEMP` ở CI — **không bao giờ** trong repo):

```bash
terraform plan -out="$PLAN_DIR/tfplan"
terraform show -json "$PLAN_DIR/tfplan" > "$PLAN_DIR/tfplan.json"
conftest test --policy policy/terraform "$PLAN_DIR/tfplan.json"
conftest verify --policy policy/terraform                   # unit test Rego (main_test.rego)
terraform plan -destroy -out="$PLAN_DIR/teardown.tfplan"    # teardown cũng vậy
```

⚠️ `tfplan.json` **không được nằm trong `infra/`** khi chạy checkov:
`scripts/verify.py` copy nguyên `infra/` rồi chạy `checkov -d .`, checkov sẽ
quét cả plan JSON — nơi không có inline `#checkov:skip` — và fail lại các
accepted risk ở Mục 10 (đã gặp thật 2026-09-25: CKV2_AWS_57, CKV2_AWS_50...).
`.gitignore` đã chặn `infra/**/tfplan.json` nhưng file vẫn tồn tại trên đĩa
local/runner, nên phải ghi ra ngoài `infra/`.

⚠️ **File plan trong `infra/` còn làm lệch `source_sha256`** (không chỉ làm
checkov fail). `fingerprint()` hash **mọi file** dưới `SOURCE_ROOTS` (có
`infra`), đi bằng `os.walk`, **không dùng git** → `.gitignore` không có tác
dụng. `source_files()` chỉ bỏ qua thư mục trong `EXCLUDED_DIRS` và tên file
`.env*`/`*.pyc`/`*.log`/`*.zip`/`*.html`/report — **không bỏ qua `tfplan`,
`tfplan.json`, `teardown.tfplan`, `lab.tfplan`**. Plan nằm lại trong `infra/`
ở local nhưng không có trên runner CI → `source_sha256` local ≠ CI → verify
FAIL ở bước so khớp `source-manifest.json`. Đã đo thật 2026-09-25: có 3 file
plan (`infra/tfplan`, `infra/teardown.tfplan`,
`infra/bootstrap/github-oidc/tfplan`) → `6e7de32b…`; chuyển ra
`/tmp/insighthub-plans/` → `0456ae13…`. **Quy tắc: mọi `terraform plan`,
`terraform show -json`, `terraform plan -destroy` đều ghi ra ngoài repo.**
Chi tiết `EXCLUDED_DIRS`: `infra/DAY3-CHECKLIST.md` mục K.

**Môi trường chạy verifier**: `scripts/verify.py` cần **Python 3.11+** và
chạy pytest bằng chính `sys.executable`, nên phải gọi bằng interpreter của
venv đã cài dependency theo `GETTING_STARTED.md` mục "Milestone verifier
dependencies":

```bash
python3.11 -m venv venv
venv/bin/python -m pip install --require-hashes -r scripts/requirements-verification.txt
venv/bin/python scripts/verify.py day3 --ci-profile github --ci-repo <owner/repo> --ci-run-id <id>
```

Pipeline CI phải làm **đúng như vậy** (`actions/setup-python` pin 3.11+,
`pip install --require-hashes`, không `pip install pytest` tự do). Venv đặt
ở root repo (`venv/`) không ảnh hưởng fingerprint vì root không thuộc
`SOURCE_ROOTS` và `venv`/`.venv` nằm trong `EXCLUDED_DIRS`.

**Danh sách rule (`main.rego`, 19 rule `deny`)** — resource đang bị xoá
(`actions == ["delete"]` hoặc `after == null`) được bỏ qua qua `is_active()`:

| Nhóm | Resource | Rule |
|---|---|---|
| Tags | mọi resource có `tags_all` | Đủ và không rỗng: `project`, `environment`, `owner`, `cost_center`, `managed_by`, `ExpiresAt` |
| Encryption | `aws_db_instance` | `storage_encrypted` phải true |
| Encryption | `aws_elasticache_replication_group` | `at_rest_encryption_enabled` phải true |
| Encryption | `aws_elasticache_replication_group` | `transit_encryption_enabled` phải true |
| Encryption | `aws_ecr_repository` | Phải có `encryption_configuration` |
| Encryption | `aws_ecr_repository` | `encryption_type` phải là `KMS` |
| TLS | `aws_db_instance` | `parameter_group_name` phải trỏ tới 1 `aws_db_parameter_group` **có trong plan** với `parameter {name = "rds.force_ssl", value = "1"}` — thiếu PG / PG không có trong plan / giá trị ≠ `"1"` → deny (fail-closed). Kiểm được qua plan vì `name` PG và `parameter_group_name` cố định (biết trước lúc plan); đã xác nhận trên plan core thật 2026-09-25 |
| Version pin | `aws_db_instance` | `engine_version` bắt đầu bằng `16` |
| Version pin | `aws_elasticache_replication_group` | `engine_version` bắt đầu bằng `7` |
| Not public | `aws_db_instance` | `publicly_accessible` không được true |
| Not public | `aws_security_group` | Ingress `0.0.0.0/0` không được phủ port 5432/6379 |
| Not public | `aws_security_group` | Ingress `::/0` không được phủ port 5432/6379 |
| Not public | `aws_eks_cluster` | `vpc_config[0].public_access_cidrs` không chứa `0.0.0.0/0` |
| Cost | `aws_eks_node_group` | `instance_types` ⊆ {`t3.medium`} |
| Cost | `aws_db_instance` | `instance_class` ∈ {`db.t3.micro`} |
| Cost | `aws_elasticache_replication_group` | `node_type` ∈ {`cache.t3.micro`} |
| Cost | `aws_nat_gateway` | Cấm tạo mới |
| Cost | `aws_db_instance` | `multi_az` không được true |
| IAM | `aws_iam_role_policy_attachment` | Cấm `policy_arn` kết thúc bằng `/AdministratorAccess` |

Rule encryption dùng `not is_true(v)` với mặc định `null` → **thiếu field
cũng bị tính là vi phạm** (fail-closed). Rule "not public"/`multi_az` dùng
`is_true(v)` với mặc định `false` → chỉ deny khi giá trị bật rõ ràng.

**Helper `is_true(v)`** — chấp nhận cả boolean `true` **và** chuỗi `"true"`.
Lý do: hashicorp/aws 5.x (pin 5.100.0) serialize
`aws_elasticache_replication_group.at_rest_encryption_enabled` dưới dạng
**string** `"true"`/`"false"` trong `resource_changes[].change.after` (schema
`TypeString` vì lý do lịch sử của provider), trong khi
`transit_encryption_enabled`/`storage_encrypted`/`publicly_accessible`/`multi_az`
là boolean. So sánh thẳng `v == true` sẽ **false-positive** deny trên plan
thật dù đã bật encryption. Dùng chung 1 helper cho mọi field boolean để rule
không phụ thuộc vào kiểu serialize của từng field/phiên bản provider.

**Conftest bù cho CKV_AWS_38**: checkov phải `#checkov:skip=CKV_AWS_38` (Mục
10) vì `public_access_cidrs = var.admin_cidrs` không có default, checkov
không resolve tĩnh được và không đọc `validation` block. Rule
`aws_eks_cluster` ở trên (giữ **deny**, không hạ xuống warn) đọc **giá trị
thật** trong plan JSON, nên nếu `admin_cidrs` vô tình chứa `0.0.0.0/0` (ví
dụ `validation` bị sửa/bỏ) thì
gate vẫn chặn trước apply — skip của checkov không còn là lỗ hổng không ai
kiểm.

**Kiểm thử**:
- `conftest verify --policy policy/terraform` — `main_test.rego`, 27 test (pass/deny cho từng rule; `rds.force_ssl`: allow có PG, deny thiếu `parameter_group_name`, deny PG không có trong plan, deny `value = "0"`).
- `tests/milestones/day3/test_policy.py` — 2 test bắt buộc của verifier
  (`test_policy_allows_valid`, `test_policy_denies_unsafe`) chạy Conftest qua
  subprocess trên `tests/milestones/day3/fixtures/{valid,invalid}_plan.json`;
  test deny kiểm cả nội dung message (thêm `rds.force_ssl`), không chỉ exit
  code. Fixture dùng địa chỉ theo module (`module.data.aws_db_instance.postgres`...);
  `valid_plan.json` có `aws_db_parameter_group` với `rds.force_ssl = "1"`.
- Plan core thật sau refactor (2026-09-25, `$PLAN_DIR/core.tfplan`, 49 to
  add): `conftest test` → 19 passed, 0 failures.
- Rule chạy trên plan **core** (resource AWS). Plan platform chỉ có
  `kubernetes_*` (không `tags_all`) nên không có rule nào áp dụng.

## 12. CI — plan/apply, saved plan, tạm thêm IP runner (THIẾT KẾ, chưa viết workflow)

Quyết định của tôi: **GitHub-hosted runner + AWS OIDC**. Hệ quả: IP runner
thay đổi mỗi job và không nằm trong `admin_cidrs` → runner không gọi được
EKS public endpoint. Core không cần cluster (không có provider kubernetes)
nên plan/apply core chạy bình thường; chỉ platform + Helm + smoke cần mở
tạm endpoint cho runner.

**Job plan** (environment `infra-plan`, role `gh_plan`):
1. `terraform -chdir=infra plan -out="$RUNNER_TEMP/core.tfplan"` → `show -json`
   → Conftest → Infracost.
2. Tính `sha256sum core.tfplan`, upload lên
   `s3://do2603-lamduy2002-insighthub-tfstate/plans/<run_id>/core.tfplan`
   với `--sse aws:kms --sse-kms-key-id <tfplan key>` (IAM từ chối nếu thiếu).
   Checksum ghi vào output job (không phải secret). **Không** upload plan làm
   GitHub artifact.

**Job apply** (environment `production` — required reviewer duyệt trước khi
job nhận được OIDC token của `gh_apply`):
1. Tải `plans/<run_id>/core.tfplan`, so `sha256sum` với checksum của job
   plan → khác thì dừng. `terraform apply core.tfplan` (đúng plan đã duyệt),
   rồi xóa object plan khỏi S3.
2. Lấy IP public runner: `RUNNER_IP=$(curl -fsS https://checkip.amazonaws.com)`.
3. `aws eks update-cluster-config --name insighthub-lab --resources-vpc-config
   publicAccessCidrs=<admin_cidrs>,$RUNNER_IP/32` → lấy `update.id` →
   poll `aws eks describe-update` tới `Successful` (fail/timeout → dừng,
   vẫn chạy bước khôi phục). Quyền: `eks:UpdateClusterConfig` +
   `eks:DescribeUpdate` chỉ trên ARN cluster lab.
4. **Platform**: `terraform -chdir=infra/platform plan -out="$RUNNER_TEMP/platform.tfplan"`
   → `terraform show "$RUNNER_TEMP/platform.tfplan"` **in ra log** →
   `terraform apply "$RUNNER_TEMP/platform.tfplan"` — apply đúng file plan
   đó, không bao giờ `apply` không qua plan.
5. Helm (ALB controller, Secrets Store CSI + ASCP, app) + smoke test.
6. Bước `if: always()`: `aws eks update-cluster-config` khôi phục **đúng**
   `admin_cidrs` (lấy từ cùng nguồn biến Terraform, không tự sinh) → poll
   `describe-update` tới `Successful`. Nếu bước khôi phục fail → job fail
   rõ ràng (endpoint đang mở thêm 1 IP /32 của runner — xử lý tay ngay).
7. Fresh `terraform -chdir=infra plan -detailed-exitcode` → phải exit 0
   (không thay đổi). **Không dùng `ignore_changes`** cho
   `public_access_cidrs`: nếu bước khôi phục lệch, fresh plan sẽ phát hiện
   drift thay vì che đi.

**Trade-off có chủ đích — platform không có human review riêng**: platform
chỉ gồm namespace + 2 ServiceAccount (annotation IRSA lấy từ output core đã
được review ở plan core). Plan platform được **in trong log** nhưng không
dừng chờ duyệt riêng trước apply — approval của environment `production`
(trước bước 1) là lần duyệt duy nhất. Chấp nhận vì phạm vi thay đổi nhỏ,
xác định hoàn toàn bởi output core; nếu platform mở rộng thêm resource có
quyền/chi phí thì phải tách job + environment duyệt riêng.

Ràng buộc liên quan: EKS chỉ cho 1 update cluster config chạy tại một thời
điểm — bước 3/6 phải chờ `Successful` trước khi làm việc khác đụng cluster
config; job apply dùng `concurrency` group để 2 run không chồng nhau.

**Job `security-scan` — bắt buộc quét thêm bản render dev.** `checkov -d infra/`
chỉ render chart bằng **values mặc định**, mà mặc định có `ingress.enabled: false`
và `secretsStore.enabled: false` → **`Ingress` và `SecretProviderClass` không
bao giờ được quét**. Đây là lỗ hổng phạm vi không vá được bằng placeholder
(Checkov không nhận `--values` theo từng chart — xem Mục 13). Job phải làm
thêm một bước riêng:

```bash
helm template insighthub infra/helm/insighthub -n insighthub-dev \
  -f infra/helm/insighthub/values-dev.yaml \
  --set image.api.tag=ci --set image.web.tag=ci --set image.worker.tag=ci \
  --set-file migration.initSql=infra/db/init.sql \
  > "$RUNNER_TEMP/render-dev/manifests.yaml"
checkov -d "$RUNNER_TEMP/render-dev" --framework kubernetes   # exit phải = 0
```

`-n insighthub-dev` ở đây để bản render sát thực tế (một số template dùng
`.Release.Namespace`, ví dụ `API_INTERNAL_URL` của web). **Nó KHÔNG giải quyết
được CKV_K8S_21**: Helm không ghi `metadata.namespace` vào manifest, nên checkov
vẫn thấy `default` dù có `-n`. Đã đo thật 2026-09-29 — giả thuyết "truyền `-n`
là hết dương tính giả" **sai**, vẫn phải dùng `checkov.io/skip` như mọi resource
khác.

Job này từng đỏ vì đúng một lý do: `Ingress` là resource **duy nhất chỉ xuất
hiện trong bản render dev**, và nó là resource duy nhất bị **quên** annotation
`checkov.io/skip` cho CKV_K8S_21. Chính lỗ hổng phạm vi mà job này sinh ra để
vá đã lộ ra một suppression còn thiếu — đúng mục đích của nó.

`values-dev.yaml` đã chứa sẵn ARN/cert giả (account `000000000000`,
`certificate/0000…`) đủ để qua guard mà không lộ giá trị thật. Bước này chạy
trên thư mục render tạm, **không** commit manifest vào repo (giữ nguyên tắc
một nguồn duy nhất là chart).

**Deploy dev truyền digest, không truyền tag.** Sau khi push image lên ECR,
job lấy digest rồi truyền vào Helm — đóng CKV_K8S_43 ở môi trường thật
(Mục 10b) và loại bỏ hoàn toàn khả năng tag trỏ sai image:

```bash
DIGEST=$(aws ecr describe-images --repository-name insighthub/api \
  --image-ids imageTag="$GIT_SHA" --query 'imageDetails[0].imageDigest' --output text)
helm upgrade --install insighthub infra/helm/insighthub ... \
  --set image.api.tag="$GIT_SHA" --set image.api.digest="$DIGEST"
```

(Chart ghép thành `repo:tag@digest` — digest thắng khi có cả hai, xem
`insighthub.image` trong `_helpers.tpl`.)


## 13. Helm charts (`infra/helm/`) — bố cục và cơ chế placeholder

### Hai chart, tách theo ranh giới môi trường

| Chart | Nội dung | Dùng ở đâu |
|---|---|---|
| `insighthub` | web/api/worker Deployment + Service + HPA + Ingress (ALB) + SecretProviderClass + migration Job | **Cả hai** — kind (`values-local.yaml`) và EKS (`values-dev.yaml`) |
| `insighthub-local-deps` | Postgres (pgvector) + Redis + Secret kết nối + **ServiceAccount `insighthub`** + NetworkPolicy | **Chỉ kind** |

### ServiceAccount không thuộc chart app (2026-09-29)

Chart `insighthub` **không có template ServiceAccount nào**. SA `insighthub`
phải tồn tại **trước** release, ở cả hai môi trường:

| Môi trường | Ai tạo SA | Ghi chú |
|---|---|---|
| dev (EKS) | Terraform root platform (`kubernetes_service_account.insighthub`) | Kèm annotation `eks.amazonaws.com/role-arn` (IRSA, MH6) |
| local (kind) | Chart `insighthub-local-deps` (cài trước chart app) | SA trần, không annotation — local không có IRSA |

Vì sao không để chart app tự tạo: migration Job là hook `pre-install,pre-upgrade`
và chạy **bằng SA này**, mà hook luôn chạy trước resource thường → SA tạo
trong cùng release đến quá muộn. Bản trước lách bằng cách biến chính SA thành
hook `hook-weight: "-20"`, kéo theo 2 hệ quả xấu: (1) SA thành resource
**không được release sở hữu** (không có annotation `meta.helm.sh/release-name`),
`helm uninstall` không xoá, teardown phải xoá tay; (2) hai môi trường tạo SA
theo 2 cơ chế khác nhau. Chuyển sang local-deps làm cả hai môi trường cùng
một hình dạng: SA có sẵn, chart app chỉ tham chiếu theo tên.

`serviceAccount.create` giữ lại trong values (`false` ở cả `values.yaml`,
`values-local.yaml`, `values-dev.yaml`) **làm guard, không phải công tắc**:
đặt `true` thì `insighthub.serviceAccountName` gọi `fail` ngay lúc render với
thông báo chỉ ra đúng nơi tạo SA — thay vì im lặng chạy bằng SA không có IRSA.

⚠️ Khi nâng cấp từ bản cũ trên một cluster đã cài: SA cũ (do hook tạo) không
có ownership metadata của Helm nên `helm upgrade insighthub-deps` sẽ từ chối
nhận quyền sở hữu (`invalid ownership metadata`). Phải
`kubectl -n <ns> delete sa insighthub` trước rồi mới upgrade — an toàn vì mọi
pod đều `automountServiceAccountToken: false`.

Tách làm 2 chart để ràng buộc "values AWS KHÔNG được có StatefulSet"
(DAY3-CHECKLIST N.10/O.12) là **bất biến theo cấu trúc**, không phụ thuộc
người cài có nhớ truyền đúng values hay không: chart app không chứa
template StatefulSet nào, nên không có đường nào cài nhầm datastore lên EKS.

### Vì sao values mặc định là placeholder

Checkov quét chart bằng cách gọi `helm template <chart>` (`checkov/helm/runner.py:349`).
Nó **không truyền được values theo từng chart**:

- Cờ `--var-file` có tồn tại và được chuyển thành `helm template --values`,
  nhưng đường dẫn giải theo **cwd của tiến trình checkov**. `checkov -d infra/`
  chạy từ repo root (cwd = repo root) còn `scripts/verify.py:525-529` copy
  `infra/` ra scratch rồi chạy `checkov -d .` với **cwd = scratch/infra** —
  không có đường dẫn tương đối nào đúng cho cả hai.
- Cùng file đó còn bị runner `terraform` nhận nhầm là tfvars →
  `Parsing errors: 1`.

Trước khi sửa, hai `fail` guard trong chart làm `helm template` với values
mặc định lỗi ngay, checkov chỉ in `[WARNI] Failed processing helm chart` rồi
**bỏ qua toàn bộ chart app** — 30 finding không bao giờ lộ ra, mà exit code
vẫn 0 nên không ai biết.

Cách xử lý: values mặc định mang **placeholder hợp lệ về cú pháp** để render
được, còn guard được gắn điều kiện ngữ cảnh.

| Values | Placeholder | Hằng số đối chiếu trong `_helpers.tpl` |
|---|---|---|
| `image.<svc>.tag` | `0.0.0-placeholder` | `insighthub.imageTagPlaceholder` |
| `migration.initSql` | dòng bắt đầu bằng `-- PLACEHOLDER` | `insighthub.initSqlPlaceholderPrefix` |

⚠️ Hai chuỗi này phải khớp từng ký tự giữa `values.yaml` và `_helpers.tpl` —
đổi một bên mà quên bên kia thì guard mất tác dụng và placeholder lọt ra
deploy thật.

### Phân biệt render tĩnh với deploy thật — `insighthub.isTemplateRender`

`helm template <chart>` không truyền tên release → Helm điền tên mặc định
`release-name`. Deploy thật luôn có tên (`helm install insighthub`,
`helm upgrade insighthub`). Guard chỉ `fail` khi tên **khác** `release-name`.

Đã thử và loại các cách khác:

- `.Capabilities.APIVersions` — **không dùng được từ Helm 3.22**: render
  offline đã điền đầy đủ version set (đo thật: `apiextensions.k8s.io/v1`,
  `batch/v1`, `autoscaling/v2` đều `true`), giống hệt khi có cluster.
- `.Capabilities.KubeVersion` — offline trả `v1.37.0` (bản compiled sẵn của
  Helm), trùng được với version cluster thật → không phân biệt được.
- `.Release.IsInstall` — `true` ở **cả hai** ngữ cảnh.

**Giới hạn đã biết**: `helm install release-name ./chart` sẽ lách được guard.
Chấp nhận — tên đó không dùng ở local lẫn CI.

### Ma trận kiểm chứng guard (chạy lại khi sửa `_helpers.tpl`)

| # | Lệnh | Kỳ vọng |
|---|---|---|
| 1 | `helm template infra/helm/insighthub` | render OK (đây là cách checkov gọi) |
| 2 | `helm install insighthub … --dry-run` thiếu tag | FAIL — `image cho component worker vẫn là tag placeholder` |
| 3 | `helm install insighthub … --dry-run` có tag, thiếu `initSql` | FAIL — `migration.initSql vẫn là placeholder` |
| 4 | `helm install insighthub … --dry-run` đủ tag + `--set-file` | OK |
| 5 | Dùng `image.<svc>.digest` thay tag | OK (digest thắng tag) |
| 6 | `helm template insighthub … --set serviceAccount.create=true` | FAIL — `serviceAccount.create phải là false: chart insighthub không tạo ServiceAccount` |
| 7 | `helm template … -f values-local.yaml` và `-f values-dev.yaml` | Không có object `kind: ServiceAccount` nào; pod spec vẫn `serviceAccountName: insighthub` |

### Phạm vi checkov KHÔNG phủ được

Values mặc định có `ingress.enabled: false` và `secretsStore.enabled: false`
→ `Ingress` và `SecretProviderClass` không nằm trong bản render mà checkov
quét. Bù lại bằng bước render dev riêng trong job `security-scan` (Mục 12).

### Đóng gói deterministic

`scripts/package-chart.sh` đóng gói chart app thành archive **byte-for-byte
giống nhau** qua mỗi lần chạy (`helm package` không deterministic: nhúng
mtime từng file vào tar và timestamp vào header gzip). Dùng cho source
binding của pipeline (Mục 12, DAY3-CHECKLIST O.9). Kiểm bằng
`bash scripts/package-chart.sh --verify` — gói 2 lần, so sha256.
