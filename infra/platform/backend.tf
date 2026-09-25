# Root PLATFORM — key riêng, cùng bucket với core. Không có biến trong
# backend block (Terraform không hỗ trợ interpolation ở đây).
terraform {
  backend "s3" {
    bucket       = "do2603-lamduy2002-insighthub-tfstate"
    key          = "insighthub/platform/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
