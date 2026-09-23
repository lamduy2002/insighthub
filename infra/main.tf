# ============================================================
# Network — VPC, public subnet, Internet Gateway, route table
# (SPEC.md Mục 2: Network — Terraform tự tạo)
# ============================================================

resource "aws_vpc" "lab" {
  #checkov:skip=CKV2_AWS_11:VPC Flow Logs tang chi phi luu tru (S3/CloudWatch) lien tuc, production-grade auditing ngoai pham vi lab theo luot - xem SPEC.md muc 10
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
  #checkov:skip=CKV_AWS_130:EKS node group can public IP de ra internet, khong NAT Gateway (chi phi $0) - RDS/Redis da chuyen sang private subnet - xem SPEC.md muc 10
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

# Private subnet cho RDS/Redis (MH5) — idx 2/3 để không trùng CIDR 2 subnet
# public (idx 0/1). Không NAT Gateway: RDS/Redis không cần ra internet, chỉ
# cần giao tiếp nội bộ VPC (route local ngầm định AWS tự thêm cho mọi route
# table, không cần khai báo) — chi phí thêm $0 so với dùng subnet public.
locals {
  private_subnet_cidrs = {
    for idx, az in var.availability_zones :
    az => cidrsubnet(var.vpc_cidr, 8, idx + 2)
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnet_cidrs

  vpc_id                  = aws_vpc.lab.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${each.key}"
  })
}

# Route table riêng, KHÔNG có route ra IGW/NAT — chỉ route local (VPC CIDR)
# AWS tự thêm ngầm định cho mọi route table, đủ để RDS/Redis giao tiếp với
# EKS node/control-plane trong cùng VPC.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
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
# dùng alias/aws/eks có sẵn của AWS — đơn giản/chắc chắn hơn vì alias mặc
# định chỉ tồn tại nếu tài khoản đã từng dùng EKS envelope encryption trước
# đó; tạo key riêng đảm bảo `terraform plan/apply` luôn chạy được, không
# phụ thuộc lịch sử tài khoản.
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "eks" {
  description             = "CMK cho EKS Secrets Encryption - ${var.eks_cluster_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 7

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
  #checkov:skip=CKV_AWS_39:Khong tat hoan toan endpoint public vi chua co VPN/bastion, ngoai pham vi Day 3 - da gioi han public_access_cidrs - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_37:Full control-plane logging phat sinh chi phi CloudWatch Logs lien tuc, khong can cho lab ngan han - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_38:public_access_cidrs lay tu var.operator_cidrs (bat buoc truyen, co validation chan 0.0.0.0/0) nhung checkov khong resolve tinh duoc gia tri - xem SPEC.md muc 10
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids             = [for s in aws_subnet.public : s.id]
    endpoint_public_access = true
    # Bật thêm private access (ENI ngay trong VPC hiện có, không cần subnet
    # riêng/NAT) để node group tự join cluster qua đường private trong VPC —
    # public_access_cidrs hẹp (chỉ IP operator) chặn cả IP public của chính
    # node nên node không join được nếu chỉ có public access.
    endpoint_private_access = true

    # Giới hạn endpoint public chỉ cho IP của người vận hành lab (CKV_AWS_38)
    # — thay vì mở 0.0.0.0/0 mặc định. Truyền qua var.operator_cidrs (không
    # tự dò IP bằng data "http") để plan deterministic giữa local và CI.
    public_access_cidrs = var.operator_cidrs
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
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags       = local.common_tags
}

resource "aws_db_instance" "postgres" {
  #checkov:skip=CKV_AWS_118:Enhanced Monitoring tang chi phi, can them IAM role rieng, khong can cho kiem chung ingestion pipeline trong lab - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_226:Co y pin engine_version de dam bao reproducibility trong luot lab - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_161:IAM authentication can sua code ket noi DB trong api/ingestion-worker, ngoai pham vi ha tang Day 3 - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_353:Performance Insights tang chi phi, production-grade observability khong can cho lab - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_293:Deletion protection mau thuan voi yeu cau terraform destroy sach sau moi luot lab - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_129:Export log RDS tang chi phi va rui ro log du lieu nhay cam - xem SPEC.md muc 10
  #checkov:skip=CKV_AWS_157:Multi-AZ tang gap doi chi phi RDS, vuot ngan sach luot lab - xem SPEC.md muc 10
  #checkov:skip=CKV2_AWS_30:Query Logging tang chi phi va cung rui ro log du lieu nhay cam nhu CKV_AWS_129 - xem SPEC.md muc 10
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

  # Miễn phí, không ảnh hưởng vận hành — áp dụng cho automated backup
  # snapshot trong vòng đời instance (khác skip_final_snapshot, chỉ tránh
  # final snapshot lúc destroy). Đóng CKV2_AWS_60 bằng code thay vì skip.
  copy_tags_to_snapshot = true

  tags = local.common_tags
}

resource "aws_elasticache_subnet_group" "lab" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]
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
  #checkov:skip=CKV_AWS_191:at_rest_encryption_enabled=true (AWS managed key) da du cho lab, CMK rieng them chi phi/do phuc tap khong can thiet - xem SPEC.md muc 10
  #checkov:skip=CKV2_AWS_50:Multi-AZ failover can >=2 cache cluster, tang gap doi chi phi Redis, lab co y dung num_cache_clusters=1 - xem SPEC.md muc 10
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
  #checkov:skip=CKV_AWS_149:Default AWS managed key (aws/secretsmanager) da ma hoa at-rest du cho secret chi ton tai trong thoi gian luot lab - xem SPEC.md muc 10
  #checkov:skip=CKV2_AWS_57:Automatic rotation can Lambda rieng + wiring bo sung, ngoai pham vi Day 3; secret bi xoa ngay khi destroy (recovery_window_in_days=0) - xem SPEC.md muc 10
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
  #checkov:skip=CKV_AWS_149:Default AWS managed key (aws/secretsmanager) da ma hoa at-rest du cho secret chi ton tai trong thoi gian luot lab - xem SPEC.md muc 10
  #checkov:skip=CKV2_AWS_57:Automatic rotation can Lambda rieng + wiring bo sung, ngoai pham vi Day 3; secret bi xoa ngay khi destroy (recovery_window_in_days=0) - xem SPEC.md muc 10
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

# ServiceAccount cho ALB Controller — chuyển từ infra/k8s/alb-controller-sa.yaml
# (apply thủ công qua kubectl) sang quản lý bằng Terraform, lấy ARN động từ
# aws_iam_role.alb_controller thay vì hardcode trong YAML.
resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }

  depends_on = [aws_eks_node_group.lab]
}

# ============================================================
# Kubernetes — namespace app + IRSA cho pod (SPEC MH3/MH6, §2.3)
# ============================================================

resource "kubernetes_namespace" "insighthub_dev" {
  metadata {
    name = "insighthub-${var.environment}"
  }

  depends_on = [aws_eks_node_group.lab]
}

# IRSA cho pod app (web/api/worker) — đọc credential DB/Redis trực tiếp từ
# Secrets Manager qua SDK, không cần mount Secret K8s plaintext lâu dài.
resource "aws_iam_role" "insighthub_app" {
  name = "${var.project_name}-app-role"

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
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:insighthub-${var.environment}:insighthub"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

# Chỉ 2 action đọc secret, đúng 2 ARN secret của app — không dùng "*" hay
# secretsmanager:* (MH6: least-privilege IRSA).
resource "aws_iam_role_policy" "insighthub_app_secrets" {
  name = "${var.project_name}-app-secrets-read"
  role = aws_iam_role.insighthub_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      Resource = [
        aws_secretsmanager_secret.db.arn,
        aws_secretsmanager_secret.redis.arn,
      ]
    }]
  })
}

resource "kubernetes_service_account" "insighthub" {
  metadata {
    name      = "insighthub"
    namespace = kubernetes_namespace.insighthub_dev.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.insighthub_app.arn
    }
  }
}

# ============================================================
# ECR — image repository cho web/api/ingestion-worker (MH10 chuẩn bị)
# ============================================================

resource "aws_ecr_repository" "app" {
  for_each = toset(["api", "web", "ingestion-worker"])

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  # AWS managed key (aws/ecr) thay vì mặc định AES256 — đóng CKV_AWS_136
  # bằng code, không dùng CMK riêng (aws_kms_key.eks) để tránh phải sửa
  # key policy cấp quyền pull image cho node role.
  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = local.common_tags
}
