variable "aws_region" {
  description = "AWS region tạo IAM role (IAM là global nhưng cần region cho provider)."
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Tên project, dùng làm prefix tên role."
  type        = string
  default     = "insighthub"
}

variable "owner" {
  description = "Chủ sở hữu, dùng cho tag owner."
  type        = string
  default     = "lamduy2002"
}

variable "cost_center" {
  description = "Mã cost center, dùng cho tag cost_center."
  type        = string
  default     = "DO2603"
}

variable "github_repo" {
  description = "owner/repo GitHub, dùng cho tài liệu/tra cứu. KHÔNG dùng dựng điều kiện trust — xem github_sub_claim_prefix."
  type        = string
  default     = "lamduy2002/insighthub"
}

variable "github_sub_claim_prefix" {
  description = <<-EOT
    Tiền tố claim `sub` mà GitHub Actions THỰC SỰ phát ra, dùng dựng điều kiện
    trust OIDC. KHÔNG tự ghép từ `github_repo`.

    Repo này bật **immutable subject claim**: `sub` chứa ID số bất biến của
    owner và repo chứ không phải tên, ví dụ
    `repo:lamduy2002@95230728/insighthub@1362359532:environment:infra-plan`.
    Dùng `repo:<owner>/<repo>:...` sẽ luôn bị AWS từ chối với
    "Not authorized to perform sts:AssumeRoleWithWebIdentity" — đã gặp thật
    (2026-09-29, run 36542501865).

    Lấy giá trị đúng bằng:
      gh api /repos/<owner>/<repo>/actions/oidc/customization/sub
    → trả `{"use_immutable_subject": true, "sub_claim_prefix": "..."}`.
    Dùng đúng `sub_claim_prefix` đó. Nếu `use_immutable_subject` là false thì
    prefix là `repo:<owner>/<repo>`.

    Ràng theo ID số thực ra CHẶT HƠN ràng theo tên: đổi tên repo hay đổi tên
    owner không âm thầm chuyển quyền trust sang chủ thể khác.
  EOT
  type        = string
  default     = "repo:lamduy2002@95230728/insighthub@1362359532"

  validation {
    condition     = can(regex("^repo:[^:]+/[^:]+$", var.github_sub_claim_prefix))
    error_message = "github_sub_claim_prefix phải có dạng repo:<owner>[@id]/<repo>[@id] và KHÔNG kèm phần :environment:/:ref:."
  }
}

variable "state_bucket" {
  description = "Bucket S3 chứa Terraform state của module chính (infra/)."
  type        = string
  default     = "do2603-lamduy2002-insighthub-tfstate"
}

variable "state_keys" {
  description = "Key state của 2 root core (infra/) và platform (infra/platform/) — scope quyền S3 cho 2 role GitHub Actions."
  type        = list(string)
  default = [
    "insighthub/core/terraform.tfstate",
    "insighthub/platform/terraform.tfstate",
  ]
}

variable "plan_prefix" {
  description = "Prefix trong state bucket chứa saved plan (mã hóa KMS riêng). gh_plan chỉ ghi, gh_apply chỉ đọc + xóa."
  type        = string
  default     = "plans/"
}

variable "eks_cluster_name" {
  description = "Tên EKS cluster lab (infra/variables.tf) — eks:UpdateClusterConfig/DescribeUpdate chỉ cấp trên đúng ARN cluster này."
  type        = string
  default     = "insighthub-lab"
}

variable "plan_environment" {
  description = "GitHub Environment của job plan — condition sub của gh_plan."
  type        = string
  default     = "infra-plan"
}

variable "apply_environment" {
  description = "GitHub Environment của job apply (có required reviewer) — condition sub của gh_apply."
  type        = string
  default     = "production"
}

# Resource cấp account dùng chung, không xóa theo lượt lab — không cần
# expires_at/ExpiresAt như module chính (xem SPEC.md).
locals {
  common_tags = {
    project     = var.project_name
    environment = "shared"
    owner       = var.owner
    cost_center = var.cost_center
    managed_by  = "terraform"
    Class       = "DO2603"
    LabId       = "bootstrap-github-oidc"
    Persistent  = "true"
  }
}
