terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# default_tags áp local.common_tags (variables.tf) cho mọi resource do
# provider aws tạo, kể cả trong module. Không có provider kubernetes ở core
# — plan core không cần cluster sống (chạy được trên GitHub-hosted runner
# khi cluster chưa tồn tại hoặc endpoint đang khóa theo admin_cidrs).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
