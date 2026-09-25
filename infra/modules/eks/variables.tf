variable "project_name" {
  description = "Prefix tên resource."
  type        = string
}

variable "eks_cluster_name" {
  description = "Tên EKS cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet cho control-plane ENI và node group (public, không NAT)."
  type        = list(string)
}

variable "admin_cidrs" {
  description = "CIDR được phép gọi EKS public endpoint (đã validate ở root)."
  type        = list(string)
}

variable "cluster_admin_principal_arns" {
  description = "IAM principal ARN được tạo access entry + AmazonEKSClusterAdminPolicy (role CI apply + operator)."
  type        = list(string)
}

variable "node_instance_type" {
  description = "Instance type cho managed node group."
  type        = string
}

variable "node_desired_size" {
  description = "Số node mong muốn."
  type        = number
}

variable "tags" {
  description = "Tag chung gắn tường minh (bổ sung cho default_tags của provider)."
  type        = map(string)
}
