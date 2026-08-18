# ==============================================================================
# Phase 2: Declarative Vault Engine, Policy, and Auth Configuration
# Note: Applied after Vault one-time initialization (vault operator init)
# ==============================================================================

# 1. Cryptographic File Audit Device
resource "vault_audit" "file_audit" {
  count = var.vault_token != "" ? 1 : 0
  type  = "file"

  options = {
    file_path = "/vault/data/vault_audit.log"
    log_raw   = "false"
    hmac_accessor = "true"
  }
}

# 2. Dynamic Database Secrets Engine
resource "vault_mount" "db" {
  count       = var.vault_token != "" ? 1 : 0
  path        = "database"
  type        = "database"
  description = "Dynamic PostgreSQL database secrets engine"
}

# 3. PostgreSQL Database Connection
resource "vault_database_secret_backend_connection" "postgres" {
  count         = var.vault_token != "" ? 1 : 0
  backend       = vault_mount.db[0].path
  name          = var.postgres_db
  allowed_roles = ["payments-app", "payments-app-prod"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${var.postgres_host}:${var.postgres_port}/${var.postgres_db}?sslmode=disable"
    username       = var.postgres_admin_user
    password       = var.postgres_admin_password
  }
}

# 4. Demo Dynamic Role (TTL: 1m / 2m)
resource "vault_database_secret_backend_role" "payments_app" {
  count               = var.vault_token != "" ? 1 : 0
  backend             = vault_mount.db[0].path
  name                = "payments-app"
  db_name             = vault_database_secret_backend_connection.postgres[0].name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT ALL PRIVILEGES ON payments TO \"{{name}}\";"
  ]
  default_ttl = 60
  max_ttl     = 120
}

# 5. Production Dynamic Role (TTL: 1h / 24h)
resource "vault_database_secret_backend_role" "payments_app_prod" {
  count               = var.vault_token != "" ? 1 : 0
  backend             = vault_mount.db[0].path
  name                = "payments-app-prod"
  db_name             = vault_database_secret_backend_connection.postgres[0].name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT ALL PRIVILEGES ON payments TO \"{{name}}\";"
  ]
  default_ttl = 3600
  max_ttl     = 86400
}

# 6. Least-Privilege Application ACL Policy
resource "vault_policy" "payments_app_policy" {
  count = var.vault_token != "" ? 1 : 0
  name  = "payments-app-policy"

  policy = <<-EOT
    path "database/creds/payments-app" {
      capabilities = ["read"]
    }
    path "database/creds/payments-app-prod" {
      capabilities = ["read"]
    }
    path "sys/leases/revoke" {
      capabilities = ["update"]
    }
  EOT
}

# 7. Secret-Less Kubernetes Auth Backend
resource "vault_auth_backend" "kubernetes" {
  count = var.vault_token != "" ? 1 : 0
  type  = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "k8s_config" {
  count                  = var.vault_token != "" ? 1 : 0
  backend                = vault_auth_backend.kubernetes[0].path
  kubernetes_host        = "https://kubernetes.default.svc:443"
  disable_iss_validation = "true"
}

resource "vault_kubernetes_auth_backend_role" "payments_app_role" {
  count                            = var.vault_token != "" ? 1 : 0
  backend                          = vault_auth_backend.kubernetes[0].path
  role_name                        = "payments-app"
  bound_service_account_names      = ["vault-dynamic-secrets"]
  bound_service_account_namespaces = ["default", "production"]
  token_policies                   = [vault_policy.payments_app_policy[0].name]
  token_ttl                        = 3600
  token_max_ttl                    = 86400
}
