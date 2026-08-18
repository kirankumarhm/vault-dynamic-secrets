# ==============================================================================
# Module: modules/vault_cluster
# Purpose: Deploys 3-Node Raft High-Availability HashiCorp Vault Helm release
#          with AWS KMS Auto-Unseal, mTLS, and File Audit Logging.
# ==============================================================================

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = var.vault_helm_version
  namespace  = var.vault_namespace

  values = [
    yamlencode({
      global = {
        enabled    = true
        tlsDisable = false
      }
      serviceName = "vault-internal"
      server = {
        image = {
          repository = "hashicorp/vault"
          tag        = var.vault_image_tag
          pullPolicy = "IfNotPresent"
        }
        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
        }
        dataStorage = {
          enabled      = true
          size         = "256Mi"
          storageClass = ""
        }
        auditStorage = {
          enabled      = true
          size         = "128Mi"
          storageClass = ""
        }
        standalone = {
          enabled = false
        }
        ha = {
          enabled  = true
          replicas = var.vault_replicas
          raft = {
            enabled   = true
            setNodeId = true
            config = <<-EOT
              ui = true
              cluster_name = "vault-production-cluster"

              listener "tcp" {
                address            = "[::]:8200"
                cluster_address    = "[::]:8201"
                tls_cert_file      = "/vault/userconfig/${var.tls_server_secret_name}/tls.crt"
                tls_key_file       = "/vault/userconfig/${var.tls_server_secret_name}/tls.key"
                tls_client_ca_file = "/vault/userconfig/${var.tls_ca_secret_name}/ca.crt"
              }

              storage "raft" {
                path = "/vault/data"
                retain_logs = 7
                snapshot_threshold = 16384
                trailing_logs = 0

                retry_join {
                  leader_api_addr = "https://vault-0.vault-internal:8200"
                  leader_ca_cert_file = "/vault/userconfig/${var.tls_ca_secret_name}/ca.crt"
                  leader_client_cert_file = "/vault/userconfig/${var.tls_server_secret_name}/tls.crt"
                  leader_client_key_file = "/vault/userconfig/${var.tls_server_secret_name}/tls.key"
                }
                retry_join {
                  leader_api_addr = "https://vault-1.vault-internal:8200"
                  leader_ca_cert_file = "/vault/userconfig/${var.tls_ca_secret_name}/ca.crt"
                  leader_client_cert_file = "/vault/userconfig/${var.tls_server_secret_name}/tls.crt"
                  leader_client_key_file = "/vault/userconfig/${var.tls_server_secret_name}/tls.key"
                }
                retry_join {
                  leader_api_addr = "https://vault-2.vault-internal:8200"
                  leader_ca_cert_file = "/vault/userconfig/${var.tls_ca_secret_name}/ca.crt"
                  leader_client_cert_file = "/vault/userconfig/${var.tls_server_secret_name}/tls.crt"
                  leader_client_key_file = "/vault/userconfig/${var.tls_server_secret_name}/tls.key"
                }
              }

              seal "awskms" {
                region                 = "${var.aws_region}"
                kms_key_id             = "${var.kms_key_id}"
                endpoint               = "${var.use_floci ? var.floci_pod_kms_endpoint : ""}"
                skip_region_validation = ${var.use_floci}
              }

              service_registration "kubernetes" {}
            EOT
          }
        }
        extraEnvironmentVars = {
          VAULT_CACERT       = "/vault/userconfig/${var.tls_ca_secret_name}/ca.crt"
          AWS_REGION         = var.aws_region
          AWS_DEFAULT_REGION = var.aws_region
          AWS_ENDPOINT_URL   = var.use_floci ? var.floci_pod_kms_endpoint : ""
        }
        extraSecretEnvironmentVars = [
          {
            envName    = "AWS_ACCESS_KEY_ID"
            secretName = var.credentials_secret_name
            secretKey  = "access-key"
          },
          {
            envName    = "AWS_SECRET_ACCESS_KEY"
            secretName = var.credentials_secret_name
            secretKey  = "secret-key"
          }
        ]
        extraVolumes = [
          {
            type = "secret"
            name = var.tls_server_secret_name
          },
          {
            type = "secret"
            name = var.tls_ca_secret_name
          }
        ]
        readinessProbe = {
          enabled             = true
          path                = "/v1/sys/health?standbyok=true&sealedcode=503&uninitcode=501"
          initialDelaySeconds = 10
          periodSeconds       = 5
          timeoutSeconds      = 3
          failureThreshold    = 3
        }
        livenessProbe = {
          enabled = false
        }
        audit = {
          file = {
            enabled = true
          }
        }
      }
      ui = {
        enabled      = true
        serviceType  = "ClusterIP"
        externalPort = 8200
      }
      injector = {
        enabled  = true
        replicas = 1
      }
    })
  ]
}
