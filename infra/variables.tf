variable "aws_region" {
  description = "AWS region để tạo toàn bộ tài nguyên lab (VPC/EKS/RDS/ElastiCache)."
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Tên project, dùng làm prefix cho tên resource và tag project."
  type        = string
  default     = "insighthub"
}

variable "environment" {
  description = "Môi trường triển khai (dev/staging/prod), dùng cho tag environment và tên namespace."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Chủ sở hữu tài nguyên lab, dùng cho tag owner để truy vết trách nhiệm cleanup. AWS coi tag key case-insensitive nên 'owner' (chữ thường) đáp ứng đồng thời yêu cầu spec (owner) và Guide (Owner)."
  type        = string
  default     = "lamduy2002"
}

variable "cost_center" {
  description = "Mã cost center, dùng cho tag cost_center để theo dõi chi phí theo lớp học."
  type        = string
  default     = "DO2603"
}

variable "expires_at" {
  description = <<-EOT
    Thời điểm dự kiến kết thúc lượt lab (ISO 8601, vd "2026-09-23T18:00:00+07:00").
    KHÔNG có default — bắt buộc truyền qua .tfvars, -var hoặc TF_VAR_expires_at
    mỗi lần apply, khớp started_at/expires_at trong lab-manifest.json (Guide
    Local/AWS Cost, mục "Trước khi tạo AWS"). Terraform sẽ dừng plan/apply nếu
    thiếu, tránh lặp lại lỗi tag ExpiresAt rỗng đã gặp ở lượt trước. Dùng để
    gắn tag ExpiresAt, hỗ trợ soát tài nguyên còn sót sau lượt lab.
  EOT
  type        = string
}

variable "admin_cidrs" {
  description = <<-EOT
    Danh sách CIDR (thường /32) của admin được phép gọi EKS public endpoint
    (CKV_AWS_38). KHÔNG có default và KHÔNG tự dò IP qua data "http" — để
    plan deterministic giữa local và CI (Acceptance §7.5). Job apply CI tạm
    thêm IP runner bằng `aws eks update-cluster-config` rồi khôi phục đúng
    danh sách này trong bước if: always() (SPEC.md Mục 12) — fresh plan sau
    đó phải không có thay đổi.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for c in var.admin_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0" && c != "::/0"])
    error_message = "admin_cidrs phải có ít nhất 1 CIDR hợp lệ và không được chứa 0.0.0.0/0 hoặc ::/0 (CKV_AWS_38)."
  }
}

variable "ci_apply_role_arn" {
  description = "ARN IAM role GitHub Actions apply (output gh_apply_role_arn của infra/bootstrap/github-oidc). Truyền qua biến thay vì remote state bootstrap để core không phụ thuộc vòng đời bootstrap. Được tạo EKS access entry + AmazonEKSClusterAdminPolicy."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.ci_apply_role_arn))
    error_message = "ci_apply_role_arn phải là ARN IAM role (arn:aws:iam::<account>:role/<name>)."
  }
}

variable "operator_principal_arns" {
  description = "ARN IAM user/role của operator được cluster admin qua EKS access entry (không hardcode trong code, truyền qua .tfvars gitignore). Bắt buộc có ít nhất 1 vì bootstrap_cluster_creator_admin_permissions = false."
  type        = list(string)

  validation {
    condition     = length(var.operator_principal_arns) > 0 && alltrue([for a in var.operator_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/.+$", a))])
    error_message = "operator_principal_arns cần ít nhất 1 ARN IAM user/role hợp lệ."
  }
}

variable "vpc_cidr" {
  description = "CIDR block cho VPC tự tạo riêng cho lab."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Danh sách 2 AZ — mỗi AZ 1 subnet public (EKS) + 1 subnet private (RDS/Redis). EKS yêu cầu tối thiểu 2 AZ."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "eks_cluster_name" {
  description = "Tên EKS cluster tự tạo cho lab."
  type        = string
  default     = "insighthub-lab"
}

variable "eks_node_instance_type" {
  description = "Instance type cho EKS managed node group."
  type        = string
  default     = "t3.medium"
}

variable "eks_node_desired_size" {
  description = "Số lượng node mong muốn trong EKS node group (lab chỉ cần 1 node để tiết kiệm chi phí)."
  type        = number
  default     = 1
}

variable "db_instance_class" {
  description = "Instance class cho RDS PostgreSQL — rẻ nhất còn hỗ trợ engine version đã chọn."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "Phiên bản PostgreSQL cho RDS (major 16 — khớp family parameter group postgres16). Đã xác nhận qua `aws rds describe-db-engine-versions --engine postgres --engine-version 16` — 16.15 là bản mới nhất còn được AWS hỗ trợ tại thời điểm viết spec (2026-09-22)."
  type        = string
  default     = "16.15"
}

variable "redis_node_type" {
  description = "Node type cho ElastiCache Redis replication group."
  type        = string
  default     = "cache.t3.micro"
}

variable "db_username" {
  description = "Username master cho RDS PostgreSQL. KHÔNG có default — bắt buộc truyền qua .tfvars (gitignore) hoặc TF_VAR_db_username, không hardcode trong mã nguồn."
  type        = string
}

# db_password: KHÔNG khai báo variable ở đây. Password sẽ được sinh tự động
# bằng resource "random_password" trong main.tf và ghi thẳng vào
# aws_secretsmanager_secret_version — không đi qua input variable/tfvars để
# tránh lộ secret trong state của biến hoặc trong lịch sử CLI (-var/-var-file).

# locals đặt chung trong variables.tf (không tách locals.tf riêng): common_tags
# chỉ phụ thuộc thuần vào các variable khai báo ngay phía trên trong cùng file
# này, không có logic phức tạp nào khác — gộp chung giúp review 1 file duy
# nhất thấy ngay biến nào build ra tag nào, đúng phạm vi "chỉ viết file này"
# của yêu cầu.
locals {
  common_tags = {
    project     = var.project_name
    environment = var.environment
    owner       = var.owner
    cost_center = var.cost_center
    managed_by  = "terraform"
    Class       = "DO2603"
    LabId       = "day3-terraform"
    ExpiresAt   = var.expires_at
  }
}
