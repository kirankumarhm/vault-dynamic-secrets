variable "environment" {
  type        = string
  description = "Deployment environment name (e.g. prod, staging, dev)."
  default     = "prod"
}

variable "cluster_name" {
  type        = string
  description = "Kubernetes / EKS cluster identifier."
  default     = "vault-floci"
}
