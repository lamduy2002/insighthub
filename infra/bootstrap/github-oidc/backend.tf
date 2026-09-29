# Backend S3 riêng cho module bootstrap — cùng bucket state với module chính
# (infra/) nhưng key khác, vì đây là resource cấp ACCOUNT dùng chung cả lớp,
# vòng đời khác hẳn hạ tầng lab theo lượt (không destroy theo lượt — xem
# lifecycle { prevent_destroy = true } trong main.tf và SPEC.md).
terraform {
  backend "s3" {
    bucket       = "do2603-lamduy2002-insighthub-tfstate"
    key          = "insighthub/bootstrap/github-oidc.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
