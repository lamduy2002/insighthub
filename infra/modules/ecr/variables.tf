variable "project_name" {
  description = "Prefix tên repository (<project>/<name>)."
  type        = string
}

variable "repositories" {
  description = "Danh sách image repository cần tạo."
  type        = list(string)
}

variable "tags" {
  description = "Tag chung gắn tường minh (bổ sung cho default_tags của provider)."
  type        = map(string)
}
