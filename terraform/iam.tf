# ==============================================================================
# IAM Policy: Least-Privilege Permissions for Vault Auto-Unseal & S3 Backups
# ==============================================================================
resource "aws_iam_policy" "vault_unseal_policy" {
  name        = "vault-autounseal-policy-prod"
  description = "Allows Vault to perform KMS auto-unseal operations and manage S3 backups"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VaultKMSUnseal"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.vault_unseal.arn
      },
      {
        Sid    = "VaultS3Backups"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.vault_backups.arn,
          "${aws_s3_bucket.vault_backups.arn}/*"
        ]
      }
    ]
  })
}

# ==============================================================================
# IAM User & Access Key (Emulates IRSA / IAM credentials for Vault Pod)
# ==============================================================================
resource "aws_iam_user" "vault_unseal" {
  name = "vault-autounseal-prod"
  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_user_policy_attachment" "vault_unseal_attach" {
  user       = aws_iam_user.vault_unseal.name
  policy_arn = aws_iam_policy.vault_unseal_policy.arn
}

resource "aws_iam_access_key" "vault_unseal_key" {
  user = aws_iam_user.vault_unseal.name
}

# Injects the AWS Credentials into the Kubernetes Secret in namespace 'vault'
resource "kubernetes_secret" "floci_credentials" {
  metadata {
    name      = "floci-credentials"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  data = {
    "access-key" = aws_iam_access_key.vault_unseal_key.id
    "secret-key" = aws_iam_access_key.vault_unseal_key.secret
  }

  type = "Opaque"
}
