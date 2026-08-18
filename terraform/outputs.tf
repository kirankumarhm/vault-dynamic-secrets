output "kms_key_id" {
  description = "AWS KMS Customer Master Key ID used for Vault Auto-Unseal"
  value       = aws_kms_key.vault_unseal.key_id
}

output "kms_key_arn" {
  description = "AWS KMS Customer Master Key ARN"
  value       = aws_kms_key.vault_unseal.arn
}

output "s3_backup_bucket" {
  description = "AWS S3 Bucket created for Vault Raft Snapshots"
  value       = aws_s3_bucket.vault_backups.bucket
}

output "vault_namespace" {
  description = "Kubernetes Namespace where Vault is deployed"
  value       = kubernetes_namespace.vault.metadata[0].name
}

output "vault_helm_status" {
  description = "Status of the Vault Helm release"
  value       = helm_release.vault.status
}
