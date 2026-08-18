output "kms_key_id" {
  description = "AWS KMS Key ID for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.key_id
}

output "kms_key_arn" {
  description = "AWS KMS Key ARN"
  value       = aws_kms_key.vault_unseal.arn
}

output "s3_bucket_name" {
  description = "S3 Bucket Name for Raft backups"
  value       = aws_s3_bucket.vault_backups.bucket
}

output "s3_bucket_arn" {
  description = "S3 Bucket ARN"
  value       = aws_s3_bucket.vault_backups.arn
}
