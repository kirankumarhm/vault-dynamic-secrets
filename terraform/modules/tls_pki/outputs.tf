output "ca_cert_pem" {
  description = "Root CA certificate in PEM format"
  value       = tls_self_signed_cert.ca_cert.cert_pem
}

output "vault_cert_pem" {
  description = "Vault Server TLS certificate in PEM format"
  value       = tls_locally_signed_cert.vault_cert.cert_pem
}

output "tls_ca_secret_name" {
  description = "Kubernetes Secret name for CA certificate"
  value       = kubernetes_secret.tls_ca.metadata[0].name
}

output "tls_server_secret_name" {
  description = "Kubernetes Secret name for Server TLS certificate"
  value       = kubernetes_secret.tls_server.metadata[0].name
}

output "vault_namespace" {
  description = "Vault Kubernetes namespace created by the module"
  value       = kubernetes_namespace.vault.metadata[0].name
}
