output "vpc_id" {
  description = "ID VPC lab."
  value       = aws_vpc.lab.id
}

output "public_subnet_ids" {
  description = "ID subnet public (EKS cluster/node group, ALB)."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "ID subnet private (RDS/Redis)."
  value       = [for s in aws_subnet.private : s.id]
}
