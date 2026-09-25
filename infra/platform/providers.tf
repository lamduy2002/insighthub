terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Endpoint/CA lấy từ output core (remote state) — không hardcode. Chỉ plan/
# apply được khi cluster đang sống VÀ IP máy chạy nằm trong public_access_cidrs
# (admin_cidrs, hoặc IP runner đã được tạm thêm trong job apply — SPEC.md Mục 12).
provider "kubernetes" {
  host                   = data.terraform_remote_state.core.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.core.outputs.eks_cluster_certificate_authority_data)

  # exec thay vì token tĩnh (~15 phút) — luôn lấy token mới mỗi lần cần auth.
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.core.outputs.eks_cluster_name, "--region", var.aws_region]
  }
}
