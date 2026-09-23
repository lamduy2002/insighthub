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
  description = "owner/repo GitHub dùng làm điều kiện trust OIDC (định dạng đúng repo:<owner>/<repo>:...)."
  type        = string
  default     = "lamduy2002/insighthub"
}

variable "state_bucket" {
  description = "Bucket S3 chứa Terraform state của module chính (infra/)."
  type        = string
  default     = "do2603-lamduy2002-insighthub-tfstate"
}

variable "state_key" {
  description = "Key state của module chính (infra/) — dùng để scope quyền S3 cho 2 role GitHub Actions."
  type        = string
  default     = "insighthub/day3-terraform/terraform.tfstate"
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
