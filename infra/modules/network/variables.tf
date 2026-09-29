variable "project_name" {
  description = "Prefix tên resource."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block cho VPC lab."
  type        = string
}

variable "availability_zones" {
  description = "Danh sách AZ — mỗi AZ 1 subnet public + 1 subnet private."
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "Tên EKS cluster, dùng cho tag kubernetes.io/cluster/<name> trên subnet public."
  type        = string
}

variable "tags" {
  description = "Tag chung gắn tường minh (bổ sung cho default_tags của provider)."
  type        = map(string)
}
