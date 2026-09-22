# ============================================================
# Network — VPC, public subnet, Internet Gateway, route table
# (SPEC.md Mục 2: Network — Terraform tự tạo)
# ============================================================

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # bắt buộc cho EKS (DNS nội bộ cluster)

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

# Chia var.vpc_cidr (10.20.0.0/16) thành các subnet /24, mỗi AZ 1 subnet.
# Dùng for_each theo AZ (key ổn định) thay vì count để tránh subnet bị
# tạo/xóa lại toàn bộ nếu thứ tự var.availability_zones thay đổi.
locals {
  public_subnet_cidrs = {
    for idx, az in var.availability_zones :
    az => cidrsubnet(var.vpc_cidr, 8, idx)
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnet_cidrs

  vpc_id                  = aws_vpc.lab.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true # node/pod ra internet trực tiếp, không cần NAT (SPEC Mục 2)

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-${each.key}"
    # Bắt buộc để AWS Load Balancer Controller tự nhận diện subnet đặt ALB
    "kubernetes.io/role/elb" = "1"
    # Bắt buộc để EKS/ALB Controller nhận diện subnet thuộc cluster nào
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Khóa default SG của VPC (CKV2_AWS_12) — không khai ingress/egress nào =>
# Terraform revoke hết rule allow-all mặc định. Không resource nào trong
# main.tf gán vào default SG này (RDS/Redis dùng aws_security_group.data
# riêng), nên khóa lại không ảnh hưởng traffic hợp lệ.
resource "aws_default_security_group" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-default-sg-locked"
  })
}

# ============================================================
# Compute — EKS cluster, node group, IAM role, OIDC provider
# (SPEC.md Mục 2: Compute)
# ============================================================

# IP public hiện tại của máy chạy Terraform — dùng để giới hạn
# public_access_cidrs của EKS endpoint (CKV_AWS_38). Phải chạy lại
# `terraform apply` mỗi khi đổi mạng/IP, vì đây là whitelist theo IP thật.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# KMS CMK riêng cho EKS Secrets Encryption (CKV_AWS_58). Tạo mới thay vì
# dùng alias/aws/eks có sẵn của AWS — đơn giản/chắc chắn hơn vì alias mặc
# định chỉ tồn tại nếu tài khoản đã từng dùng EKS envelope encryption trước
# đó; tạo key riêng đảm bảo `terraform plan/apply` luôn chạy được, không
# phụ thuộc lịch sử tài khoản.
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "eks" {
  description         = "CMK cho EKS Secrets Encryption - ${var.eks_cluster_name}"
  enable_key_rotation = true

  # Policy tường minh (CKV2_AWS_64) — nội dung tương đương default policy
  # của AWS (root account full access, ủy quyền quản lý qua IAM) + thêm rõ
  # ràng quyền cho chính cluster role dùng key.
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

  tags = local.common_tags
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# Cluster role cần quyền dùng CMK này để mã hóa/giải mã Kubernetes Secrets
# (bắt buộc cho encryption_config, không tự động có qua AmazonEKSClusterPolicy).
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

  tags = local.common_tags
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
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids             = [for s in aws_subnet.public : s.id]
    endpoint_public_access = true
    # endpoint_private_access không set — mặc định false, không cần vì
    # không có private subnet (SPEC Mục 2/3).

    # Giới hạn endpoint public chỉ cho IP hiện tại của người vận hành lab
    # (CKV_AWS_38) — thay vì mở 0.0.0.0/0 mặc định.
    public_access_cidrs = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  tags = local.common_tags

  # Tránh race condition: IAM role phải có policy/quyền KMS trước khi EKS
  # control plane cố gắng dùng role đó.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy.eks_cluster_kms,
  ]
}

resource "aws_eks_node_group" "lab" {
  cluster_name    = aws_eks_cluster.lab.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [for s in aws_subnet.public : s.id]
  instance_types  = [var.eks_node_instance_type]

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = 1
    max_size     = 1 # lab, không cần autoscale
  }

  tags = local.common_tags

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

  tags = local.common_tags
}

# ============================================================
# Database/Cache — RDS PostgreSQL, ElastiCache Redis, Security Group
# (SPEC.md Mục 2: Database/Cache)
# ============================================================

# Không tạo SG riêng cho EKS node: node group hiện không dùng launch_template
# tùy chỉnh nên AWS tự gắn cluster security group (tạo kèm aws_eks_cluster)
# vào cả control-plane lẫn node ENI. Dùng luôn SG đó (đã có qua data source
# trong providers.tf) làm nguồn ingress cho RDS/Redis.
resource "aws_security_group" "data" {
  name        = "${var.project_name}-data-sg"
  description = "SG cho RDS PostgreSQL va ElastiCache Redis - chi cho phep ingress tu EKS cluster SG"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "PostgreSQL tu EKS cluster/node"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_eks_cluster.lab.vpc_config[0].cluster_security_group_id]
  }

  ingress {
    description     = "Redis tu EKS cluster/node"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [data.aws_eks_cluster.lab.vpc_config[0].cluster_security_group_id]
  }

  # Thu hẹp từ "-1"/toàn bộ port (CKV_AWS_382) xuống chỉ HTTPS 443 — đủ cho
  # RDS/Redis gọi AWS API (KMS, CloudWatch...) nếu cần, không có nhu cầu
  # outbound nào khác trong kiến trúc lab hiện tại (không bật IAM auth,
  # log export, hay rotation Lambda dùng chung SG này).
  egress {
    description = "HTTPS ra ngoai (AWS API/KMS), khong mo toan bo port"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# Loại trừ /, @, ", khoảng trắng — các ký tự dễ gây lỗi khi nhúng password
# vào connection string/URL (JDBC URI, .env).
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?~"
}

resource "aws_db_subnet_group" "lab" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [for s in aws_subnet.public : s.id]
  tags       = local.common_tags
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.project_name}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_encrypted = true

  db_name  = "insighthub"
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.lab.name
  vpc_security_group_ids = [aws_security_group.data.id]
  publicly_accessible    = false

  # Lab: tránh snapshot phát sinh tính phí sau khi destroy (SPEC Mục 7).
  skip_final_snapshot = true

  tags = local.common_tags
}

resource "aws_elasticache_subnet_group" "lab" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = [for s in aws_subnet.public : s.id]
  tags       = local.common_tags
}

# ElastiCache auth_token: loại trừ /, @, ", khoảng trắng (AWS không cho phép
# các ký tự này trong auth_token của Redis AUTH).
resource "random_password" "redis_auth" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?~"
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.project_name}-redis"
  description          = "Redis cho InsightHub lab (ARQ job queue)"

  engine = "redis"
  # Đã xác nhận qua `aws elasticache describe-cache-engine-versions --engine redis`
  # (2026-09-22) — 7.1 là bản mới nhất còn được hỗ trợ.
  engine_version = "7.1"
  node_type      = var.redis_node_type

  num_cache_clusters = 1 # lab, không cần replica

  subnet_group_name  = aws_elasticache_subnet_group.lab.name
  security_group_ids = [aws_security_group.data.id]

  at_rest_encryption_enabled = true
  # Bắt buộc cho CKV_AWS_30/31: mã hóa in-transit + auth_token đi kèm.
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result

  tags = local.common_tags
}

# ============================================================
# Secrets — DB credentials qua Secrets Manager
# (SPEC.md Mục 2: Secrets)
# ============================================================

resource "aws_secretsmanager_secret" "db" {
  name = "${var.project_name}/${var.environment}/db-credentials"

  # Lab: xóa ngay khi destroy, không chờ recovery window mặc định (7-30 ngày)
  # — tránh secret "treo" tính phí sau khi hạ tầng đã bị xóa.
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = "insighthub"
  })
}

# Lưu auth_token của Redis (mới bật ở phần Database/Cache, đi kèm
# transit_encryption_enabled) — không để token chỉ nằm trong Terraform
# state, pod đọc qua IRSA giống pattern DB credentials.
resource "aws_secretsmanager_secret" "redis" {
  name                    = "${var.project_name}/${var.environment}/redis-credentials"
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({
    auth_token = random_password.redis_auth.result
    host       = aws_elasticache_replication_group.redis.primary_endpoint_address
    port       = 6379
  })
}

# ============================================================
# IAM Role/Policy cho AWS Load Balancer Controller (IRSA)
# (SPEC.md Mục 2: Load Balancing — chỉ phần IAM là Terraform,
# việc cài Helm chart + tạo Ingress nằm ngoài phạm vi .tf)
# ============================================================

resource "aws_iam_role" "alb_controller" {
  name = "${var.project_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

# Dùng file policy chính thức đã tải về infra/policies/iam_policy.json
# (kubernetes-sigs/aws-load-balancer-controller) — không hardcode JSON dài
# trong main.tf.
resource "aws_iam_policy" "alb_controller" {
  name   = "${var.project_name}-alb-controller-policy"
  policy = file("${path.module}/policies/iam_policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
