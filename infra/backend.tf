# Backend S3 với native state locking (use_lockfile, Terraform >= 1.10).
# Không dùng DynamoDB lock table (deprecated theo hướng dẫn mới của AWS provider).
#
# LƯU Ý: backend "s3" block KHÔNG hỗ trợ interpolation biến (var./local.) —
# Terraform yêu cầu giá trị literal hoặc truyền qua `-backend-config` lúc init.
# Bucket "do2603-lamduy2002-insighthub-tfstate" phải được tạo thủ công TRƯỚC
# khi chạy `terraform init` (bucket này nằm ngoài phạm vi state mà Terraform
# quản lý — tránh vấn đề "con gà quả trứng").
# Root CORE — key insighthub/core/terraform.tfstate. Root platform/ dùng key
# riêng insighthub/platform/terraform.tfstate (SPEC.md Mục 2).
terraform {
  backend "s3" {
    bucket       = "do2603-lamduy2002-insighthub-tfstate"
    key          = "insighthub/core/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
