# ============================================================
# Compute — EKS cluster, node group, IAM role, KMS, OIDC provider,
# access entry (SPEC.md Mục 2: Compute)
# ============================================================

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# KMS CMK riêng cho EKS Secrets Encryption (CKV_AWS_58). Tạo mới thay vì
# dùng alias/aws/eks — alias mặc định chỉ tồn tại nếu tài khoản đã từng
# dùng EKS envelope encryption, key riêng đảm bảo plan/apply luôn chạy được.
resource "aws_kms_key" "eks" {
  description             = "CMK cho EKS Secrets Encryption - ${var.eks_cluster_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  # Policy tường minh (CKV2_AWS_64) — tương đương default policy (root
  # account full access, ủy quyền qua IAM) + quyền cho cluster role.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowEKSClusterRoleUseOfKey"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.eks_cluster.arn }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })

  tags = var.tags
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# Cluster role cần quyền dùng CMK để mã hóa/giải mã Kubernetes Secrets
# (không tự động có qua AmazonEKSClusterPolicy).
resource "aws_iam_role_policy" "eks_cluster_kms" {
  name = "${var.project_name}-eks-cluster-kms"
  role = aws_iam_role.eks_cluster.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]
      Resource = aws_kms_key.eks.arn
    }]
  })
}

resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_worker_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "lab" {
  #checkov:skip=CKV_AWS_39:Khong tat hoan toan endpoint public vi CI dung GitHub-hosted runner va chua co VPN/bastion - da gioi han public_access_cidrs theo var.admin_cidrs - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_37:Full control-plane logging phat sinh chi phi CloudWatch Logs lien tuc, khong can cho lab ngan han - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_38:public_access_cidrs lay tu var.admin_cidrs (bat buoc truyen, validation tu choi 0.0.0.0/0 va ::/0) nhung checkov khong resolve tinh duoc - Conftest kiem tra gia tri that tren plan JSON - xem SPEC.md muc 10/11
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids             = var.subnet_ids
    endpoint_public_access = true
    # Private access để node group join cluster qua đường private trong VPC —
    # public_access_cidrs hẹp chặn cả IP public của chính node.
    endpoint_private_access = true

    # Chỉ IP admin (CKV_AWS_38). Job apply CI tạm thêm IP runner ngoài
    # Terraform rồi khôi phục đúng danh sách này (SPEC.md Mục 12).
    public_access_cidrs = var.admin_cidrs
  }

  # API_AND_CONFIG_MAP: quyền cluster quản lý bằng access entry (API) thay
  # vì chỉ aws-auth ConfigMap. Tắt bootstrap creator admin: người/role tạo
  # cluster KHÔNG tự có quyền ngầm — tránh trùng với access entry khai
  # tường minh bên dưới (ResourceInUseException khi gh_apply là creator) và
  # để quyền cluster admin nằm hết trong code, review được.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = false
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  tags = var.tags

  # IAM role phải có policy/quyền KMS trước khi control plane dùng role đó.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy.eks_cluster_kms,
  ]
}

resource "aws_eks_node_group" "lab" {
  cluster_name    = aws_eks_cluster.lab.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = 1
    max_size     = 1 # lab, không cần autoscale
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker_policy,
    aws_iam_role_policy_attachment.eks_node_cni_policy,
    aws_iam_role_policy_attachment.eks_node_ecr_readonly,
  ]
}

# OIDC provider — bắt buộc cho IRSA (SPEC MH6)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.lab.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.lab.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = var.tags
}

# ============================================================
# Access entry — cluster admin cho role CI apply + operator (không hardcode
# ARN, truyền qua biến). Không cấp gì cho gh_plan: platform chỉ plan trong
# job apply (SPEC.md Mục 12).
# ============================================================
resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.cluster_admin_principal_arns)

  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = var.tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = aws_eks_access_entry.admin

  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
