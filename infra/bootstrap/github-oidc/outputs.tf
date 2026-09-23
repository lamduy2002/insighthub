output "github_oidc_provider_arn" {
  description = "ARN của GitHub Actions OIDC provider (dùng chung cả lớp DO2603)."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "gh_plan_role_arn" {
  description = "IAM Role ARN cho job plan trong GitHub Actions (trust pull_request) — dùng làm GitHub Variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.gh_plan.arn
}

output "gh_apply_role_arn" {
  description = "IAM Role ARN cho job apply trong GitHub Actions (trust environment:production) — dùng làm GitHub Variable AWS_APPLY_ROLE_ARN."
  value       = aws_iam_role.gh_apply.arn
}
