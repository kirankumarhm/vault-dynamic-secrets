# ==============================================================================
# Root Terraform Composition: Modular Architecture for Production Vault & RDS
# ==============================================================================

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
# Providers Configuration
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

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

provider "vault" {
  address         = var.vault_address
  token           = var.vault_token
  ca_cert_file    = var.vault_ca_cert_path
  skip_tls_verify = var.vault_skip_tls_verify
}

# ==============================================================================
# Module 1: AWS KMS Auto-Unseal Key & S3 Raft Backup Bucket
# ==============================================================================
module "aws_kms_s3" {
  source       = "./modules/aws_kms_s3"
  environment  = var.environment
  cluster_name = var.eks_cluster_name
}

# ==============================================================================
# Module 2: IAM Least-Privilege Policy & Credentials Secret
# ==============================================================================
module "iam_auth" {
  source          = "./modules/iam_auth"
  environment     = var.environment
  kms_key_arn     = module.aws_kms_s3.kms_key_arn
  s3_bucket_arn   = module.aws_kms_s3.s3_bucket_arn
  vault_namespace = var.vault_namespace

  depends_on = [module.tls_pki]
}

# ==============================================================================
# Module 3: Automated mTLS Root CA & Vault Server Certificates
# ==============================================================================
module "tls_pki" {
  source          = "./modules/tls_pki"
  environment     = var.environment
  vault_namespace = var.vault_namespace
}

# ==============================================================================
# Module 4: Amazon RDS PostgreSQL (AWS) or Automated In-Cluster Database (Floci)
# ==============================================================================
module "database" {
  source                  = "./modules/database"
  use_floci               = var.use_floci
  environment             = var.environment
  app_namespace           = var.app_namespace
  postgres_db             = var.postgres_db
  postgres_admin_user     = var.postgres_admin_user
  postgres_admin_password = var.postgres_admin_password
  postgres_port           = var.postgres_port
  kms_key_arn             = module.aws_kms_s3.kms_key_arn
}

# ==============================================================================
# Module 5: HashiCorp Vault 3-Node Raft HA Cluster Helm Deployment
# ==============================================================================
module "vault_cluster" {
  source                  = "./modules/vault_cluster"
  vault_namespace         = module.tls_pki.vault_namespace
  vault_helm_version      = var.vault_helm_version
  vault_image_tag         = var.vault_image_tag
  vault_replicas          = var.vault_replicas
  aws_region              = var.aws_region
  kms_key_id              = module.aws_kms_s3.kms_key_id
  use_floci               = var.use_floci
  floci_pod_kms_endpoint  = var.floci_pod_kms_endpoint
  tls_ca_secret_name      = module.tls_pki.tls_ca_secret_name
  tls_server_secret_name  = module.tls_pki.tls_server_secret_name
  credentials_secret_name = module.iam_auth.credentials_secret_name

  depends_on = [
    module.tls_pki,
    module.iam_auth,
    module.aws_kms_s3
  ]
}

# ==============================================================================
# Module 6: Vault Audit Logging, Dynamic Secrets Engine, Roles & K8s Auth
# Note: Applied in Phase 2 after Vault one-time initialization
# ==============================================================================
module "vault_configuration" {
  source                   = "./modules/vault_configuration"
  enabled                  = var.vault_token != "" ? true : false
  postgres_host            = module.database.postgres_host
  postgres_port            = module.database.postgres_port
  postgres_db              = module.database.postgres_db
  postgres_admin_user      = module.database.postgres_admin_user
  postgres_admin_password  = module.database.postgres_admin_password
  app_service_account_name = var.app_service_account_name
  app_namespace            = var.app_namespace

  depends_on = [
    module.vault_cluster,
    module.database
  ]
}
