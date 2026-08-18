variable "vault_namespace" {
  type        = string
  description = "Kubernetes namespace where Vault Helm release is deployed."
  default     = "vault"
}

variable "vault_helm_version" {
  type        = string
  description = "HashiCorp Vault Helm chart version."
  default     = "0.34.1"
}

variable "vault_image_tag" {
  type        = string
  description = "Vault container image tag."
  default     = "1.18.2"
}

variable "vault_replicas" {
  type        = number
  description = "Number of Raft HA replicas."
  default     = 3
}

variable "aws_region" {
  type        = string
  description = "AWS Region for KMS."
  default     = "us-east-1"
}

variable "kms_key_id" {
  type        = string
  description = "AWS KMS Key ID used for auto-unseal."
}

variable "use_floci" {
  type        = bool
  description = "Whether running on local Floci emulator."
  default     = true
}

variable "floci_pod_kms_endpoint" {
  type        = string
  description = "Internal container bridge IP for Floci KMS."
  default     = "http://127.0.0.1:4566"
}

variable "tls_ca_secret_name" {
  type        = string
  description = "Kubernetes Secret name containing CA certificate."
  default     = "tls-ca"
}

variable "tls_server_secret_name" {
  type        = string
  description = "Kubernetes Secret name containing server TLS certificate."
  default     = "tls-server"
}

variable "credentials_secret_name" {
  type        = string
  description = "Kubernetes Secret name containing AWS access keys."
  default     = "floci-credentials"
}
