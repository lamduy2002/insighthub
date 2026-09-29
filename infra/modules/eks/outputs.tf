output "cluster_name" {
  description = "Tên EKS cluster."
  value       = aws_eks_cluster.lab.name
}

output "cluster_arn" {
  description = "ARN EKS cluster."
  value       = aws_eks_cluster.lab.arn
}

output "cluster_endpoint" {
  description = "Endpoint API server."
  value       = aws_eks_cluster.lab.endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA (base64) của API server."
  value       = aws_eks_cluster.lab.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Cluster SG do EKS tự tạo, gắn vào control-plane và node ENI — nguồn ingress cho RDS/Redis."
  value       = aws_eks_cluster.lab.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN OIDC provider của cluster (IRSA)."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_host" {
  description = "Issuer host (không https://) dùng làm prefix condition key trong trust policy IRSA."
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}
