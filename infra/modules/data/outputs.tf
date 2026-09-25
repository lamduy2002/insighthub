output "rds_endpoint" {
  description = "Endpoint RDS (host:port)."
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Primary endpoint ElastiCache Redis."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "db_secret_arn" {
  description = "ARN secret DB credentials."
  value       = aws_secretsmanager_secret.db.arn
}

output "redis_secret_arn" {
  description = "ARN secret Redis auth token."
  value       = aws_secretsmanager_secret.redis.arn
}
