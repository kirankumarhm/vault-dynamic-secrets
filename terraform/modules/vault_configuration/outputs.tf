output "policy_name" {
  description = "Vault Least-Privilege Policy Name"
  value       = var.enabled ? vault_policy.payments_app_policy[0].name : ""
}

output "k8s_auth_role_name" {
  description = "Vault Kubernetes Auth Role Name"
  value       = var.enabled ? vault_kubernetes_auth_backend_role.payments_app_role[0].role_name : ""
}

output "demo_db_role_name" {
  description = "Demo Dynamic DB Role Name"
  value       = var.enabled ? vault_database_secret_backend_role.payments_app[0].name : ""
}

output "prod_db_role_name" {
  description = "Production Dynamic DB Role Name"
  value       = var.enabled ? vault_database_secret_backend_role.payments_app_prod[0].name : ""
}
