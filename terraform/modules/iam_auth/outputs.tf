output "iam_user_name" {
  description = "IAM user name for Vault Auto-Unseal"
  value       = aws_iam_user.vault_unseal.name
}

output "iam_policy_arn" {
  description = "IAM policy ARN attached to Vault Auto-Unseal user"
  value       = aws_iam_policy.vault_unseal_policy.arn
}

output "credentials_secret_name" {
  description = "Kubernetes Secret name containing AWS access keys"
  value       = kubernetes_secret.floci_credentials.metadata[0].name
}
