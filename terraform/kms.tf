# ==============================================================================
# AWS KMS Customer Master Key (CMK) for Vault Auto-Unseal
# ==============================================================================
resource "aws_kms_key" "vault_unseal" {
  description             = "Production HashiCorp Vault Auto-Unseal Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
    Application = "HashiCorp-Vault"
  }
}

resource "aws_kms_alias" "vault_unseal_alias" {
  name          = "alias/vault-autounseal-prod"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

# ==============================================================================
# AWS S3 Bucket for Automated Raft Cluster Snapshots & Backups
# ==============================================================================
resource "aws_s3_bucket" "vault_backups" {
  bucket        = "vault-backups-${var.eks_cluster_name}"
  force_destroy = true

  tags = {
    Environment = "production"
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
