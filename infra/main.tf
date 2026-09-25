# ============================================================
# Root CORE — hạ tầng AWS (SPEC.md Mục 2). Không có provider kubernetes:
# namespace/ServiceAccount nằm ở root platform/ (đọc output qua
# terraform_remote_state). Thứ tự apply: bootstrap → core → platform → Helm.
# ============================================================

locals {
  # Nguồn duy nhất cho namespace/SA của app: trust policy IRSA dưới đây và
  # root platform/ (qua output) cùng dùng, không khai lại ở 2 nơi.
  app_namespace            = "${var.project_name}-${var.environment}"
  app_service_account_name = "insighthub"
  alb_controller_namespace = "kube-system"
  alb_controller_sa_name   = "aws-load-balancer-controller"
}

module "network" {
  source = "./modules/network"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  eks_cluster_name   = var.eks_cluster_name
  tags               = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  project_name                 = var.project_name
  eks_cluster_name             = var.eks_cluster_name
  subnet_ids                   = module.network.public_subnet_ids
  admin_cidrs                  = var.admin_cidrs
  cluster_admin_principal_arns = distinct(concat([var.ci_apply_role_arn], var.operator_principal_arns))
  node_instance_type           = var.eks_node_instance_type
  node_desired_size            = var.eks_node_desired_size
  tags                         = local.common_tags
}

module "data" {
  source = "./modules/data"

  project_name                  = var.project_name
  environment                   = var.environment
  vpc_id                        = module.network.vpc_id
  private_subnet_ids            = module.network.private_subnet_ids
  eks_cluster_security_group_id = module.eks.cluster_security_group_id
  db_engine_version             = var.db_engine_version
  db_instance_class             = var.db_instance_class
  db_username                   = var.db_username
  redis_node_type               = var.redis_node_type
  tags                          = local.common_tags
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  repositories = ["api", "web", "ingestion-worker"]
  tags         = local.common_tags
}

# ============================================================
# IRSA — AWS Load Balancer Controller. Role + policy ở core (IAM thuần);
# ServiceAccount ở platform/, cài controller bằng Helm.
# ============================================================

resource "aws_iam_role" "alb_controller" {
  name = "${var.project_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider_host}:sub" = "system:serviceaccount:${local.alb_controller_namespace}:${local.alb_controller_sa_name}"
          "${module.eks.oidc_provider_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

# File policy chính thức (kubernetes-sigs/aws-load-balancer-controller) —
# không hardcode JSON dài trong main.tf.
resource "aws_iam_policy" "alb_controller" {
  name   = "${var.project_name}-alb-controller-policy"
  policy = file("${path.module}/policies/iam_policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# ============================================================
# IRSA — pod app (web/api/worker). Secrets Store CSI Driver + AWS provider
# mount secret bằng identity của pod (SA insighthub) — role chỉ đọc đúng 2
# secret của app (MH6: least-privilege).
# ============================================================

resource "aws_iam_role" "insighthub_app" {
  name = "${var.project_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider_host}:sub" = "system:serviceaccount:${local.app_namespace}:${local.app_service_account_name}"
          "${module.eks.oidc_provider_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

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
        module.data.db_secret_arn,
        module.data.redis_secret_arn,
      ]
    }]
  })
}
