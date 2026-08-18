# ==============================================================================
# Module: modules/aws_kms_s3
# Purpose: Provisions AWS KMS Customer Master Key for Vault Envelope Encryption &
#          S3 Bucket for Raft Cluster Snapshots / Disaster Recovery.
# ==============================================================================

resource "aws_kms_key" "vault_unseal" {
  description             = "Production HashiCorp Vault Auto-Unseal Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "HashiCorp-Vault"
  }
}

resource "aws_kms_alias" "vault_unseal_alias" {
  name          = "alias/vault-autounseal-${var.environment}"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

resource "aws_s3_bucket" "vault_backups" {
  bucket        = "vault-backups-${var.cluster_name}-${var.environment}"
  force_destroy = true

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "HashiCorp-Vault"
  }
}

resource "aws_s3_bucket_versioning" "vault_backups_versioning" {
  bucket = aws_s3_bucket.vault_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}
