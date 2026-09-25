# ============================================================
# Database/Cache/Secrets — RDS PostgreSQL, ElastiCache Redis, Security
# Group, Secrets Manager (SPEC.md Mục 2: Database/Cache, Secrets)
# ============================================================

# Không tạo SG riêng cho EKS node: node group không dùng launch_template
# tùy chỉnh nên AWS tự gắn cluster security group vào cả control-plane lẫn
# node ENI — dùng SG đó (var.eks_cluster_security_group_id) làm nguồn ingress.
resource "aws_security_group" "data" {
  name        = "${var.project_name}-data-sg"
  description = "SG cho RDS PostgreSQL va ElastiCache Redis - chi cho phep ingress tu EKS cluster SG"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL tu EKS cluster/node"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_cluster_security_group_id]
  }

  ingress {
    description     = "Redis tu EKS cluster/node"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_cluster_security_group_id]
  }

  # Thu hẹp egress xuống chỉ HTTPS 443 (CKV_AWS_382) — đủ cho gọi AWS API.
  egress {
    description = "HTTPS ra ngoai (AWS API/KMS), khong mo toan bo port"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Loại trừ /, @, ", khoảng trắng — dễ gây lỗi khi nhúng vào connection string.
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?~"
}

resource "aws_db_subnet_group" "lab" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

# Bắt buộc TLS phía server: rds.force_ssl = 1 → RDS từ chối kết nối không
# mã hóa. App (api/ingestion-worker) PHẢI kết nối với sslmode=require (kiểm
# ở bước audit app — SPEC.md Mục 2). `name` cố định (không name_prefix) để
# giá trị biết trước lúc plan — Conftest đối chiếu parameter_group_name của
# aws_db_instance với parameter group này (SPEC.md Mục 11).
resource "aws_db_parameter_group" "postgres" {
  name        = "${var.project_name}-postgres16"
  family      = "postgres16"
  description = "InsightHub PostgreSQL 16 - bat buoc TLS (rds.force_ssl=1)"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = var.tags
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
  parameter_group_name   = aws_db_parameter_group.postgres.name
  vpc_security_group_ids = [aws_security_group.data.id]
  publicly_accessible    = false

  # Lab: tránh snapshot phát sinh tính phí sau khi destroy (SPEC Mục 7).
  skip_final_snapshot = true

  # Đóng CKV2_AWS_60 bằng code (áp dụng cho automated backup snapshot).
  copy_tags_to_snapshot = true

  tags = var.tags
}

resource "aws_elasticache_subnet_group" "lab" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

# Chỉ ký tự an toàn cho URL (chữ-số + "-_"): token được nhúng nguyên văn
# vào redis_url (rediss://:<token>@host) và arq RedisSettings.from_dsn KHÔNG
# unquote password — "#", "?", "[", "]" làm hỏng urlparse, còn token đã
# percent-encode sẽ bị gửi nguyên chuỗi %XX nên AUTH fail. 32 ký tự từ 64
# ký hiệu ≈ 192 bit, đủ mạnh; ElastiCache yêu cầu 16-128 ký tự in được.
resource "random_password" "redis_auth" {
  length           = 32
  special          = true
  override_special = "-_"
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

  tags = var.tags
}

# Secrets Manager — pod đọc qua Secrets Store CSI Driver + AWS provider
# bằng IRSA (SPEC.md Mục 2: Secrets), không Secret K8s plaintext lâu dài.
resource "aws_secretsmanager_secret" "db" {
  #checkov:skip=CKV_AWS_149:Default AWS managed key (aws/secretsmanager) da ma hoa at-rest du cho secret chi ton tai trong thoi gian luot lab - xem SPEC.md muc 10
  #checkov:skip=CKV2_AWS_57:Automatic rotation can Lambda rieng + wiring bo sung, ngoai pham vi Day 3; secret bi xoa ngay khi destroy (recovery_window_in_days=0) - xem SPEC.md muc 10
  name = "${var.project_name}/${var.environment}/db-credentials"

  # Lab: xóa ngay khi destroy, tránh secret "treo" tính phí.
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = "insighthub"
    sslmode  = "require"
    # App (api/worker) chỉ đọc DATABASE_URL (psycopg conninfo) — dựng sẵn ở
    # đây vì Helm/K8s không URL-encode được. libpq percent-decode password
    # trong URI nên urlencode() giữ đúng giá trị. sslmode=require bắt buộc do
    # rds.force_ssl = 1 (verify-full + CA bundle RDS là tùy chọn).
    database_url = "postgresql://${var.db_username}:${urlencode(random_password.db.result)}@${aws_db_instance.postgres.address}:5432/insighthub?sslmode=require"
  })
}

resource "aws_secretsmanager_secret" "redis" {
  #checkov:skip=CKV_AWS_149:Default AWS managed key (aws/secretsmanager) da ma hoa at-rest du cho secret chi ton tai trong thoi gian luot lab - xem SPEC.md muc 10
  #checkov:skip=CKV2_AWS_57:Automatic rotation can Lambda rieng + wiring bo sung, ngoai pham vi Day 3; secret bi xoa ngay khi destroy (recovery_window_in_days=0) - xem SPEC.md muc 10
  name                    = "${var.project_name}/${var.environment}/redis-credentials"
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({
    auth_token = random_password.redis_auth.result
    host       = aws_elasticache_replication_group.redis.primary_endpoint_address
    port       = 6379
    # App chỉ đọc REDIS_URL (arq RedisSettings.from_dsn). rediss:// = TLS,
    # bắt buộc vì transit_encryption_enabled = true. Token URL-safe (xem
    # random_password.redis_auth) nên nhúng nguyên văn, không encode.
    redis_url = "rediss://:${random_password.redis_auth.result}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379/0"
  })
}
