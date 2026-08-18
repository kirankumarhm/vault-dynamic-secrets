variable "enabled" {
  type        = bool
  description = "Set to true when Vault is initialized and unsealed."
  default     = false
}

variable "postgres_host" {
  type        = string
  description = "PostgreSQL host address."
}

variable "postgres_port" {
  type        = number
  description = "PostgreSQL port."
  default     = 5432
}

variable "postgres_db" {
  type        = string
  description = "Target database name."
  default     = "payments"
}

variable "postgres_admin_user" {
  type        = string
  description = "PostgreSQL administrator user."
  default     = "postgres"
}

variable "postgres_admin_password" {
  type        = string
  description = "PostgreSQL administrator password."
  sensitive   = true
}

variable "app_service_account_name" {
  type        = string
  description = "Kubernetes ServiceAccount name for application authentication."
  default     = "vault-dynamic-secrets"
}

variable "app_namespace" {
  type        = string
  description = "Kubernetes namespace where application is deployed."
  default     = "default"
}
