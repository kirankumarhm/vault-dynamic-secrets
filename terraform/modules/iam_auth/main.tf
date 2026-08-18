# ==============================================================================
# Module: modules/iam_auth
# Purpose: Manages least-privilege IAM policies, IAM users, and Kubernetes Secret
#          containing AWS credentials for Vault Auto-Unseal and S3 Backups.
# ==============================================================================

resource "aws_iam_policy" "vault_unseal_policy" {
  name        = "vault-autounseal-policy-${var.environment}"
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
        Resource = var.kms_key_arn
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
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user" "vault_unseal" {
  name = "vault-autounseal-${var.environment}"
  tags = {
    Environment = var.environment
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

resource "kubernetes_secret" "floci_credentials" {
  metadata {
    name      = "floci-credentials"
    namespace = var.vault_namespace
  }

  data = {
    "access-key" = aws_iam_access_key.vault_unseal_key.id
    "secret-key" = aws_iam_access_key.vault_unseal_key.secret
  }

  type = "Opaque"
}
