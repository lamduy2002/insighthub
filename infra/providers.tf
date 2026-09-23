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

# default_tags áp local.common_tags (định nghĩa tại main.tf, Mục 2 SPEC)
# cho mọi resource do provider aws tạo — không cần khai lại tags= thủ công
# ở từng resource (vẫn có thể override/merge thêm tag riêng nếu cần).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Provider kubernetes trỏ động vào EKS cluster sẽ được tạo tại main.tf
# (aws_eks_cluster.lab) — không hardcode endpoint/CA vì cluster chưa tồn tại
# tại thời điểm plan.
data "aws_eks_cluster" "lab" {
  name = aws_eks_cluster.lab.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.lab.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.lab.certificate_authority[0].data)

  # exec thay vì data.aws_eks_cluster_auth.lab.token: token tĩnh của data
  # source chỉ sống ~15 phút kể từ lúc refresh, có thể hết hạn giữa chừng
  # apply dài (EKS cluster+node group từng mất >30 phút thực tế). exec gọi
  # `aws eks get-token` lại mỗi lần provider cần auth, luôn lấy token mới.
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.lab.name, "--region", var.aws_region]
  }
}
