output "helm_release_status" {
  description = "Vault Helm release deployment status"
  value       = helm_release.vault.status
}

output "vault_service_name" {
  description = "Vault public Service name"
  value       = "vault"
}

output "vault_internal_service_name" {
  description = "Vault headless internal Service name for Raft"
  value       = "vault-internal"
}
