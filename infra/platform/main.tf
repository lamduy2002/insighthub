# ============================================================
# Root PLATFORM — object Kubernetes nền cho Helm (SPEC.md Mục 2):
# namespace app + 2 ServiceAccount có annotation IRSA. Mọi tên/ARN đọc từ
# output core để khớp đúng condition sub của trust policy IRSA.
# ============================================================

data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = var.core_state_key
    region = var.aws_region
  }
}

locals {
  core = data.terraform_remote_state.core.outputs
}

resource "kubernetes_namespace" "app" {
  metadata {
    name = local.core.app_namespace
    labels = {
      "app.kubernetes.io/part-of"    = var.project_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_service_account" "insighthub" {
  metadata {
    name      = local.core.app_service_account_name
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = local.core.app_irsa_role_arn
    }
  }
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = local.core.alb_controller_service_account_name
    namespace = local.core.alb_controller_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = local.core.alb_controller_role_arn
    }
  }
}
