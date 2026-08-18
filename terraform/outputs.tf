output "kms_key_id" {
  description = "AWS KMS Customer Master Key ID used for Vault Auto-Unseal"
  value       = module.aws_kms_s3.kms_key_id
}

output "kms_key_arn" {
  description = "AWS KMS Customer Master Key ARN"
  value       = module.aws_kms_s3.kms_key_arn
}

output "s3_backup_bucket" {
  description = "AWS S3 Bucket created for Vault Raft Snapshots"
  value       = module.aws_kms_s3.s3_bucket_name
}

output "vault_namespace" {
  description = "Kubernetes Namespace where Vault is deployed"
  value       = module.tls_pki.vault_namespace
}

output "vault_helm_status" {
  description = "Status of the Vault Helm release"
  value       = module.vault_cluster.helm_release_status
}

output "postgres_host" {
  description = "Active PostgreSQL database host (Amazon RDS address or internal Kubernetes Service)"
  value       = module.database.postgres_host
}

output "postgres_port" {
  description = "Active PostgreSQL database port"
  value       = module.database.postgres_port
}

output "postgres_database" {
  description = "Active PostgreSQL database name"
  value       = module.database.postgres_db
}
