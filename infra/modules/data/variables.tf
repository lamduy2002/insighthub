variable "project_name" {
  description = "Prefix tên resource."
  type        = string
}

variable "environment" {
  description = "Môi trường, dùng trong tên secret (<project>/<env>/...)."
  type        = string
}

variable "vpc_id" {
  description = "VPC chứa SG data."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnet private cho RDS/Redis subnet group."
  type        = list(string)
}

variable "eks_cluster_security_group_id" {
  description = "Cluster SG của EKS — nguồn ingress duy nhất cho 5432/6379."
  type        = string
}

variable "db_engine_version" {
  description = "Phiên bản PostgreSQL (major 16, khớp family parameter group postgres16)."
  type        = string
}

variable "db_instance_class" {
  description = "Instance class RDS."
  type        = string
}

variable "db_username" {
  description = "Username master RDS."
  type        = string
}

variable "redis_node_type" {
  description = "Node type ElastiCache."
  type        = string
}

variable "tags" {
  description = "Tag chung gắn tường minh (bổ sung cho default_tags của provider)."
  type        = map(string)
}
