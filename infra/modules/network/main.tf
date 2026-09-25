# ============================================================
# Network — VPC, public subnet (EKS node), private subnet (RDS/Redis),
# Internet Gateway, route table (SPEC.md Mục 2: Network)
# ============================================================

resource "aws_vpc" "lab" {
  #checkov:skip=CKV2_AWS_11:VPC Flow Logs tang chi phi luu tru (S3/CloudWatch) lien tuc, production-grade auditing ngoai pham vi lab theo luot - xem SPEC.md muc 10
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # bắt buộc cho EKS (DNS nội bộ cluster)

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-igw"
  })
}

# Chia var.vpc_cidr thành các subnet /24, mỗi AZ 1 subnet public (idx 0/1)
# và 1 subnet private (idx 2/3). for_each theo AZ (key ổn định) thay vì
# count để subnet không bị tạo/xóa lại nếu thứ tự availability_zones đổi.
locals {
  public_subnet_cidrs = {
    for idx, az in var.availability_zones :
    az => cidrsubnet(var.vpc_cidr, 8, idx)
  }
  private_subnet_cidrs = {
    for idx, az in var.availability_zones :
    az => cidrsubnet(var.vpc_cidr, 8, idx + 2)
  }
}

resource "aws_subnet" "public" {
  #checkov:skip=CKV_AWS_130:EKS node group can public IP de ra internet, khong NAT Gateway (chi phi $0) - RDS/Redis da chuyen sang private subnet - xem SPEC.md muc 10
  for_each = local.public_subnet_cidrs

  vpc_id                  = aws_vpc.lab.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true # node/pod ra internet trực tiếp, không cần NAT (SPEC Mục 2)

  tags = merge(var.tags, {
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

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private subnet cho RDS/Redis (MH5). Không NAT Gateway: RDS/Redis không
# cần ra internet, route local (VPC CIDR) AWS tự thêm ngầm định là đủ.
resource "aws_subnet" "private" {
  for_each = local.private_subnet_cidrs

  vpc_id                  = aws_vpc.lab.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-${each.key}"
  })
}

# Route table riêng, KHÔNG có route ra IGW/NAT — chỉ route local ngầm định.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# Khóa default SG của VPC (CKV2_AWS_12) — không khai ingress/egress nào =>
# Terraform revoke hết rule allow-all mặc định. Không resource nào gán vào
# default SG này (RDS/Redis dùng SG riêng ở module data).
resource "aws_default_security_group" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-default-sg-locked"
  })
}
