output "github_oidc_provider_arn" {
  description = "ARN của GitHub Actions OIDC provider (dùng chung cả lớp DO2603)."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "gh_plan_role_arn" {
  description = "IAM Role ARN cho job plan trong GitHub Actions (trust environment:infra-plan) — dùng làm GitHub Variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.gh_plan.arn
}

output "gh_apply_role_arn" {
  description = "IAM Role ARN cho job apply trong GitHub Actions (trust environment:production) — dùng làm GitHub Variable AWS_APPLY_ROLE_ARN."
  value       = aws_iam_role.gh_apply.arn
}

output "tfplan_kms_key_arn" {
  description = "ARN KMS key mã hóa saved plan — dùng cho aws s3 cp --sse aws:kms --sse-kms-key-id (GitHub Variable TFPLAN_KMS_KEY_ARN)."
  value       = aws_kms_key.tfplan.arn
}

output "saved_plan_location" {
  description = "Vị trí lưu saved plan (s3://<bucket>/<prefix>)."
  value       = "s3://${var.state_bucket}/${var.plan_prefix}"
}
