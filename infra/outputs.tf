# Output cho root platform/ (terraform_remote_state) và Helm values.

output "aws_region" {
  description = "Region của hạ tầng core."
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID VPC lab (ALB controller cần vpcId)."
  value       = module.network.vpc_id
}

output "eks_cluster_name" {
  description = "Tên EKS cluster."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint API server của EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "CA (base64) của EKS API server — provider kubernetes ở platform."
  value       = module.eks.cluster_certificate_authority_data
}

output "app_namespace" {
  description = "Namespace app (khớp condition sub của IRSA app role)."
  value       = local.app_namespace
}

output "app_service_account_name" {
  description = "Tên ServiceAccount app (khớp condition sub của IRSA app role)."
  value       = local.app_service_account_name
}

output "app_irsa_role_arn" {
  description = "IAM role IRSA cho pod app (đọc 2 secret qua Secrets Store CSI)."
  value       = aws_iam_role.insighthub_app.arn
}

output "alb_controller_role_arn" {
  description = "IAM role IRSA cho AWS Load Balancer Controller."
  value       = aws_iam_role.alb_controller.arn
}

output "alb_controller_namespace" {
  description = "Namespace ServiceAccount ALB controller."
  value       = local.alb_controller_namespace
}

output "alb_controller_service_account_name" {
  description = "Tên ServiceAccount ALB controller (khớp condition sub)."
  value       = local.alb_controller_sa_name
}

output "db_secret_arn" {
  description = "ARN secret DB credentials (SecretProviderClass)."
  value       = module.data.db_secret_arn
}

output "redis_secret_arn" {
  description = "ARN secret Redis auth token (SecretProviderClass)."
  value       = module.data.redis_secret_arn
}

output "ecr_repository_urls" {
  description = "Map repository → URL."
  value       = module.ecr.repository_urls
}

output "rds_endpoint" {
  description = "Endpoint kết nối RDS PostgreSQL (host:port)."
  value       = module.data.rds_endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Primary endpoint ElastiCache Redis."
  value       = module.data.redis_endpoint
}
