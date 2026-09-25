variable "aws_region" {
  description = "Region của bucket state và EKS cluster."
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Tên project, dùng cho label namespace."
  type        = string
  default     = "insighthub"
}

variable "state_bucket" {
  description = "Bucket S3 chứa state core."
  type        = string
  default     = "do2603-lamduy2002-insighthub-tfstate"
}

variable "core_state_key" {
  description = "Key state của root core (infra/backend.tf)."
  type        = string
  default     = "insighthub/core/terraform.tfstate"
}
