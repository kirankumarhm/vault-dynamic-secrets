variable "use_floci" {
  type        = bool
  description = "Set to true when running on local Floci emulator; set to false for real AWS EKS production."
  default     = true
}

variable "floci_endpoint" {
  type        = string
  description = "Local Floci AWS mock endpoint."
  default     = "http://localhost:4566"
}

variable "aws_region" {
  type        = string
  description = "AWS Region for KMS, EKS, and S3 resources."
  default     = "us-east-1"
}

variable "aws_access_key" {
  type        = string
  description = "AWS Access Key ID (dummy for Floci, or provided via environment)."
  default     = "test"
}

variable "aws_secret_key" {
  type        = string
  description = "AWS Secret Access Key (dummy for Floci, or provided via environment)."
  default     = "test"
}

variable "eks_cluster_name" {
  type        = string
  description = "Kubernetes / EKS Cluster name."
  default     = "vault-floci"
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to the local kubeconfig file."
  default     = "~/.kube/config"
}

variable "vault_namespace" {
  type        = string
  description = "Kubernetes namespace for HashiCorp Vault."
  default     = "vault"
}

variable "vault_helm_version" {
  type        = string
  description = "HashiCorp Vault Helm chart version."
  default     = "0.34.1"
}

variable "vault_image_tag" {
  type        = string
  description = "HashiCorp Vault container image tag."
  default     = "1.18.2"
}

variable "vault_replicas" {
  type        = number
  description = "Number of Vault HA Raft cluster replicas."
  default     = 3
}

variable "vault_address" {
  type        = string
  description = "Address to connect to the Vault server API."
  default     = "https://127.0.0.1:8200"
}

variable "vault_token" {
  type        = string
  description = "Vault Root / Admin Token (supplied after initialization for Phase 2)."
  default     = ""
  sensitive   = true
}

variable "vault_ca_cert_path" {
  type        = string
  description = "Path to the CA certificate for Vault provider TLS verification."
  default     = ""
}

variable "vault_skip_tls_verify" {
  type        = bool
  description = "Whether to skip TLS verification for local provider bootstrapping."
  default     = true
}

variable "postgres_host" {
  type        = string
  description = "PostgreSQL hostname in Kubernetes or AWS RDS endpoint."
  default     = "postgres.default.svc.cluster.local"
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
  description = "PostgreSQL master admin username for dynamic user creation."
  default     = "postgres"
}

variable "postgres_admin_password" {
  type        = string
  description = "PostgreSQL master admin password."
  default     = "postgrespassword"
  sensitive   = true
}

variable "floci_pod_kms_endpoint" {
  type        = string
  description = "Endpoint accessible from within the Kubernetes pod network to reach Floci KMS."
  default     = "http://127.0.0.1:4566"
}
