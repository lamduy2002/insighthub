output "repository_urls" {
  description = "Map tên repository → URL (dùng cho image build/push và Helm values)."
  value       = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}
