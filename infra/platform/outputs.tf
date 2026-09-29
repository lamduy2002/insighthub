output "app_namespace" {
  description = "Namespace app đã tạo (Helm release đích)."
  value       = kubernetes_namespace.app.metadata[0].name
}

output "app_service_account_name" {
  description = "ServiceAccount app (Helm values serviceAccount.name, create=false)."
  value       = kubernetes_service_account.insighthub.metadata[0].name
}

output "alb_controller_service_account_name" {
  description = "ServiceAccount ALB controller (Helm chart serviceAccount.create=false)."
  value       = kubernetes_service_account.alb_controller.metadata[0].name
}
