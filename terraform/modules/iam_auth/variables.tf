variable "kms_key_arn" {
  type        = string
  description = "Target KMS Key ARN for unseal permission policy."
}

variable "s3_bucket_arn" {
  type        = string
  description = "Target S3 Bucket ARN for backup permission policy."
}

variable "vault_namespace" {
  type        = string
  description = "Kubernetes namespace where Vault credentials secret is created."
  default     = "vault"
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "prod"
}
