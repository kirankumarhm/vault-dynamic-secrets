variable "use_floci" {
  type        = bool
  description = "Whether running on local Floci emulator (true) or real AWS RDS (false)."
  default     = true
}

variable "app_namespace" {
  type        = string
  description = "Kubernetes namespace for application and in-cluster database."
  default     = "default"
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "prod"
}

variable "postgres_db" {
  type        = string
  description = "Database name."
  default     = "payments"
}

variable "postgres_admin_user" {
  type        = string
  description = "Database master administrator username."
  default     = "postgres"
}

variable "postgres_admin_password" {
  type        = string
  description = "Database master administrator password."
  default     = "postgrespassword"
  sensitive   = true
}

variable "postgres_port" {
  type        = number
  description = "Database port."
  default     = 5432
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN for AWS RDS storage encryption."
  default     = ""
}
