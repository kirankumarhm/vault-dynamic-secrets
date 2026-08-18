variable "vault_namespace" {
  type        = string
  description = "Kubernetes namespace for Vault."
  default     = "vault"
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "prod"
}
