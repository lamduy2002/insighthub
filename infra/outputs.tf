output "eks_cluster_name" {
  description = "Tên EKS cluster đã tạo."
  value       = aws_eks_cluster.lab.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint API server của EKS cluster."
  value       = aws_eks_cluster.lab.endpoint
}

output "rds_endpoint" {
  description = "Endpoint kết nối RDS PostgreSQL (host:port)."
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Primary endpoint kết nối ElastiCache Redis."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "alb_controller_role_arn" {
  description = "ARN của IAM Role dùng cho ServiceAccount của AWS Load Balancer Controller (IRSA)."
  value       = aws_iam_role.alb_controller.arn
}

output "vpc_id" {
  description = "ID của VPC tự tạo cho lab."
  value       = aws_vpc.lab.id
}
