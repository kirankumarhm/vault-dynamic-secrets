terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ==============================================================================
# AWS Provider: Supports both Local Floci and Real AWS EKS
# ==============================================================================
provider "aws" {
  region                      = var.aws_region
  access_key                  = var.aws_access_key
  secret_key                  = var.aws_secret_key
  skip_credentials_validation = var.use_floci
  skip_metadata_api_check     = var.use_floci
  skip_requesting_account_id  = var.use_floci

  dynamic "endpoints" {
    for_each = var.use_floci ? [1] : []
    content {
      eks = var.floci_endpoint
      kms = var.floci_endpoint
      s3  = var.floci_endpoint
      iam = var.floci_endpoint
      sts = var.floci_endpoint
    }
  }
}

# ==============================================================================
# Kubernetes & Helm Providers: Connect to Floci EKS / Real EKS
# ==============================================================================
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# ==============================================================================
# HashiCorp Vault Provider: Configured after Vault is initialized
# ==============================================================================
provider "vault" {
  address         = var.vault_address
  token           = var.vault_token
  ca_cert_file    = var.vault_ca_cert_path
  skip_tls_verify = var.vault_skip_tls_verify
}
