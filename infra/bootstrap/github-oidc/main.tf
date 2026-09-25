data "aws_caller_identity" "current" {}

# ============================================================
# OIDC Provider cho GitHub Actions — resource CẤP ACCOUNT DÙNG CHUNG
# ============================================================
# AWS chỉ cho phép 1 provider/URL issuer trên mỗi account. Trước khi viết
# module này đã chạy `aws iam list-open-id-connect-providers` xác nhận CHƯA
# có provider nào cho token.actions.githubusercontent.com trên account này
# (chỉ có 6 provider OIDC của EKS cluster do học viên khác tạo) — an toàn để
# tạo mới ở đây.
#
# Nếu học viên khác trong lớp apply song song và gặp lỗi EntityAlreadyExists:
# KHÔNG sửa code để tạo lại — chạy:
#   terraform import aws_iam_openid_connect_provider.github_actions \
#     arn:aws:iam::<account_id>:oidc-provider/token.actions.githubusercontent.com
# rồi apply lại bình thường (SPEC.md ghi chi tiết quy trình).
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = local.common_tags

  # KHÔNG destroy theo lượt lab — role của học viên khác (nếu có) có thể
  # đang trust provider này. Trước khi gỡ thủ công cuối Day 3 phải chạy
  # `aws iam list-roles` rồi lọc AssumeRolePolicyDocument tham chiếu ARN
  # provider này, chỉ gỡ khi chắc chắn không còn role nào khác trust nó
  # (xem infra/SPEC.md).
  lifecycle {
    prevent_destroy = true
  }
}

locals {
  gh_oidc_host = replace(aws_iam_openid_connect_provider.github_actions.url, "https://", "")
  account_id   = data.aws_caller_identity.current.account_id

  state_bucket_arn  = "arn:aws:s3:::${var.state_bucket}"
  state_object_arns = [for k in var.state_keys : "${local.state_bucket_arn}/${k}"]
  lock_object_arns  = [for k in var.state_keys : "${local.state_bucket_arn}/${k}.tflock"]
  plan_objects_arn  = "${local.state_bucket_arn}/${var.plan_prefix}*"
  lab_cluster_arn   = "arn:aws:eks:${var.aws_region}:${local.account_id}:cluster/${var.eks_cluster_name}"
}

# ============================================================
# Role "plan" — trust GitHub Environment "infra-plan", chỉ đọc + ghi saved
# plan mã hóa. PR từ fork không có environment/id-token nên không assume được.
# ============================================================
resource "aws_iam_role" "gh_plan" {
  name = "${var.project_name}-gh-plan-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.gh_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.gh_oidc_host}:sub" = "repo:${var.github_repo}:environment:${var.plan_environment}"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "gh_plan_readonly" {
  role       = aws_iam_role.gh_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "gh_plan_extra" {
  name = "${var.project_name}-gh-plan-extra"
  role = aws_iam_role.gh_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadAppSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.project_name}/dev/*"]
      },
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.state_bucket_arn]
        Condition = {
          StringLike = { "s3:prefix" = ["insighthub/*", "${var.plan_prefix}*"] }
        }
      },
      {
        # terraform plan chỉ ĐỌC state — không Put/Delete trên file state.
        Sid      = "StateReadOnly"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = local.state_object_arns
      },
      {
        # Native S3 lock (use_lockfile) tạo/xóa file .tflock kể cả khi plan.
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = local.lock_object_arns
      },
      {
        # Chỉ ghi saved plan vào đúng prefix, bắt buộc SSE-KMS bằng đúng key
        # tfplan (Put không kèm header mã hóa/sai key bị từ chối).
        Sid      = "WriteSavedPlan"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = [local.plan_objects_arn]
        Condition = {
          StringEquals = {
            "s3:x-amz-server-side-encryption"                = "aws:kms"
            "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.tfplan.arn
          }
        }
      },
      {
        Sid      = "EncryptSavedPlan"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"]
        Resource = [aws_kms_key.tfplan.arn]
      },
    ]
  })
}

# ============================================================
# Role "apply" — trust GitHub Environment "production", CRUD scoped theo
# đúng resource type module chính (infra/) tạo. KHÔNG dùng AdministratorAccess.
# ============================================================
resource "aws_iam_role" "gh_apply" {
  name = "${var.project_name}-gh-apply-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.gh_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.gh_oidc_host}:sub" = "repo:${var.github_repo}:environment:${var.apply_environment}"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "gh_apply_state" {
  name = "${var.project_name}-gh-apply-state"
  role = aws_iam_role.gh_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.state_bucket_arn]
        Condition = {
          StringLike = { "s3:prefix" = ["insighthub/*", "${var.plan_prefix}*"] }
        }
      },
      {
        Sid      = "StateObjectAndLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = concat(local.state_object_arns, local.lock_object_arns)
      },
      {
        # Tải saved plan đã được duyệt rồi xóa sau khi apply — không ghi.
        Sid      = "ReadAndDeleteSavedPlan"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject"]
        Resource = [local.plan_objects_arn]
      },
      {
        Sid      = "DecryptSavedPlan"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [aws_kms_key.tfplan.arn]
      },
    ]
  })
}

# EC2 (VPC/subnet/IGW/route table/SG) hầu như không hỗ trợ Resource-level ARN
# cho các action Create*/Delete*/Modify* — dùng Resource "*", nhưng giới hạn
# đúng bộ action module chính cần thay vì ec2:*.
resource "aws_iam_role_policy" "gh_apply_network" {
  #checkov:skip=CKV_AWS_355:EC2 Create/Delete/Modify cho VPC/subnet/IGW/route table/SG khong ho tro Resource-level ARN, bat buoc "*" - da gioi han dung bo action can - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_290:Cung nguyen nhan CKV_AWS_355 - action ghi di kem Resource "*" do gioi han API, khong phai thieu rang buoc chu y - xem SPEC.md muc 10
  name = "${var.project_name}-gh-apply-network"
  role = aws_iam_role.gh_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway", "ec2:DescribeInternetGateways",
        "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables",
        "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
        "ec2:DescribeNetworkInterfaces", "ec2:DescribeAvailabilityZones", "ec2:DescribeAccountAttributes",
        "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "gh_apply_eks" {
  name = "${var.project_name}-gh-apply-eks"
  role = aws_iam_role.gh_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ClusterAndNodegroupLifecycle"
        Effect = "Allow"
        Action = [
          "eks:CreateCluster", "eks:DeleteCluster", "eks:DescribeCluster",
          "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:DescribeNodegroup", "eks:UpdateNodegroupConfig",
          "eks:TagResource", "eks:UntagResource", "eks:ListTagsForResource",
        ]
        Resource = [
          "arn:aws:eks:${var.aws_region}:${local.account_id}:cluster/${var.project_name}-*",
          "arn:aws:eks:${var.aws_region}:${local.account_id}:nodegroup/${var.project_name}-*/*/*",
        ]
      },
      {
        # Đổi public_access_cidrs (Terraform + bước tạm thêm/khôi phục IP
        # runner — SPEC.md Mục 12): CHỈ trên đúng cluster lab, không wildcard.
        Sid      = "UpdateLabClusterConfig"
        Effect   = "Allow"
        Action   = ["eks:UpdateClusterConfig", "eks:DescribeUpdate"]
        Resource = [local.lab_cluster_arn]
      },
      {
        Sid    = "ManageLabAccessEntries"
        Effect = "Allow"
        Action = [
          "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:DescribeAccessEntry", "eks:UpdateAccessEntry",
          "eks:ListAccessEntries", "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy",
          "eks:ListAssociatedAccessPolicies",
        ]
        Resource = [
          local.lab_cluster_arn,
          "arn:aws:eks:${var.aws_region}:${local.account_id}:access-entry/${var.eks_cluster_name}/*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy" "gh_apply_data" {
  #checkov:skip=CKV_AWS_355:ElastiCache/KMS Create truoc khi resource ton tai bat buoc Resource "*" (khong co ARN co dinh) - da gioi han dung bo action can - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_290:Cung nguyen nhan CKV_AWS_355 - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_289:kms:PutKeyPolicy/CreateGrant bi coi la "permissions management" nhung bat buoc Resource "*" truoc khi CMK ton tai - xem SPEC.md muc 10
  name = "${var.project_name}-gh-apply-data"
  role = aws_iam_role.gh_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RdsScoped"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance", "rds:DeleteDBInstance", "rds:DescribeDBInstances", "rds:ModifyDBInstance",
          "rds:CreateDBSubnetGroup", "rds:DeleteDBSubnetGroup", "rds:DescribeDBSubnetGroups",
          "rds:CreateDBParameterGroup", "rds:DeleteDBParameterGroup", "rds:ModifyDBParameterGroup",
          "rds:DescribeDBParameterGroups", "rds:DescribeDBParameters",
          "rds:AddTagsToResource", "rds:RemoveTagsFromResource", "rds:ListTagsForResource",
        ]
        Resource = [
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:db:${var.project_name}-*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subgrp:${var.project_name}-*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:pg:${var.project_name}-*",
        ]
      },
      {
        # ElastiCache subnet-group/replication-group ARN không hỗ trợ đủ các
        # action trên để scope chặt hơn Resource "*" (một số action ElastiCache
        # bắt buộc "*", tương tự bộ quyền đã tự cấp cho DE000215 ở lượt trước).
        Sid    = "ElastiCacheScoped"
        Effect = "Allow"
        Action = [
          "elasticache:CreateReplicationGroup", "elasticache:DeleteReplicationGroup", "elasticache:DescribeReplicationGroups",
          "elasticache:CreateCacheSubnetGroup", "elasticache:DeleteCacheSubnetGroup", "elasticache:DescribeCacheSubnetGroups",
          "elasticache:AddTagsToResource", "elasticache:RemoveTagsFromResource", "elasticache:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerScoped"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:PutSecretValue",
          "secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret",
          "secretsmanager:TagResource", "secretsmanager:UntagResource",
        ]
        Resource = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/dev/*"]
      },
      {
        Sid    = "EcrScoped"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
          "ecr:PutImageTagMutability", "ecr:PutImageScanningConfiguration", "ecr:TagResource", "ecr:UntagResource",
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}/*"
      },
      {
        # kms:CreateKey bắt buộc Resource "*"; các action còn lại trên CMK
        # cũng thường yêu cầu "*" trước khi key tồn tại (không có ARN cố định
        # trước CreateKey) — tương tự bộ quyền đã tự cấp cho DE000215.
        Sid    = "KmsScoped"
        Effect = "Allow"
        Action = [
          "kms:CreateKey", "kms:ScheduleKeyDeletion", "kms:DescribeKey", "kms:PutKeyPolicy",
          "kms:EnableKeyRotation", "kms:CreateAlias", "kms:DeleteAlias",
          "kms:TagResource", "kms:UntagResource", "kms:ListResourceTags", "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "gh_apply_iam" {
  name = "${var.project_name}-gh-apply-iam"
  role = aws_iam_role.gh_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageAppRolesAndPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
          "iam:TagRole", "iam:UntagRole",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_name}-*",
        ]
      },
      {
        # OIDC provider CỦA EKS CLUSTER (IRSA app/ALB controller) — khác hẳn
        # provider GitHub Actions ở module bootstrap này. Mỗi lượt lab tạo
        # 1 provider mới (gắn theo issuer URL riêng của cluster đó).
        Sid    = "ManageEksOidcProvider"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/*"
      },
      {
        Sid    = "PassEksRoles"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-eks-cluster-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-eks-node-role",
        ]
        Condition = {
          StringEquals = { "iam:PassedToService" = ["eks.amazonaws.com", "ec2.amazonaws.com"] }
        }
      },
    ]
  })
}

# ============================================================
# ECR push — image build trong job apply (MH10). GetAuthorizationToken
# không hỗ trợ resource-level (API chỉ nhận "*"); các action còn lại chỉ
# trên repository của project.
# ============================================================
resource "aws_iam_role_policy" "gh_apply_ecr_push" {
  name = "${var.project_name}-gh-apply-ecr-push"
  role = aws_iam_role.gh_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushProjectRepos"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:DescribeImages",
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/${var.project_name}/*"
      },
    ]
  })
}

# ============================================================
# KMS key cho saved plan (plans/ trong state bucket). Saved plan chứa giá
# trị nhạy cảm dạng plaintext (random_password DB/Redis) → mã hóa bằng CMK
# riêng, chỉ gh_plan được encrypt và gh_apply được decrypt; KHÔNG upload
# plan làm GitHub artifact (repo public). Bucket tạo tay, ngoài state
# Terraform → ép mã hóa bằng condition IAM của gh_plan, không bucket policy.
# ============================================================
resource "aws_kms_key" "tfplan" {
  description             = "CMK ma hoa Terraform saved plan (${var.plan_prefix}) cho GitHub Actions"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "PlanRoleEncrypt"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.gh_plan.arn }
        Action    = ["kms:GenerateDataKey", "kms:Encrypt", "kms:DescribeKey"]
        Resource  = "*"
      },
      {
        Sid       = "ApplyRoleDecrypt"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.gh_apply.arn }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "tfplan" {
  name          = "alias/${var.project_name}-tfplan"
  target_key_id = aws_kms_key.tfplan.key_id
}
