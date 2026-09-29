# ============================================================
# ECR — image repository cho web/api/ingestion-worker (MH10)
# ============================================================

resource "aws_ecr_repository" "app" {
  for_each = toset(var.repositories)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  # AWS managed key (aws/ecr) — đóng CKV_AWS_136 bằng code, không dùng CMK
  # riêng để khỏi sửa key policy cấp quyền pull cho node role.
  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = var.tags
}
