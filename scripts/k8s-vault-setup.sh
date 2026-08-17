#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# Script: scripts/k8s-vault-setup.sh
# Purpose: Production-Grade Automated Vault Configuration on Kubernetes / Floci
#          1. Enables File Audit Logging (/vault/data/vault_audit.log)
#          2. Enables & Configures Database Engine for PostgreSQL 18.4
#          3. Creates Demo Role 'payments-app' (1m default / 2m max TTL)
#          4. Creates Production Role 'payments-app-prod' (1h default / 24h max TTL)
#          5. Configures Least-Privilege Policy 'payments-app-policy'
#          6. Configures Secret-Less Kubernetes Auth (ServiceAccount token)
#          7. Configures AppRole Auth (Alternative auth fallback)
# ==============================================================================

VAULT_POD="${VAULT_POD:-vault-0}"
VAULT_NS="${VAULT_NS:-vault}"
PG_HOST="${PG_HOST:-postgres.default.svc.cluster.local}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-payments}"
PG_ADMIN_USER="${PG_ADMIN_USER:-postgres}"
PG_ADMIN_PASS="${PG_ADMIN_PASS:-postgrespassword}"
VAULT_TOKEN="${VAULT_TOKEN:?'VAULT_TOKEN must be exported before running this script (e.g. export VAULT_TOKEN=$(jq -r .root_token vault-init.json))'}"

# Injects VAULT_TOKEN into every exec so the pod environment receives it.
vexec() { kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- env VAULT_TOKEN="${VAULT_TOKEN}" "$@"; }

echo "==> 1. Ensuring Vault Cryptographic File Audit Device is enabled..."
vexec vault audit enable file file_path=/vault/data/vault_audit.log 2>/dev/null \
  && echo "    Audit device enabled (/vault/data/vault_audit.log)" || echo "    Audit device already enabled"

echo "==> 2. Ensuring Database Secrets Engine is enabled..."
vexec vault secrets enable -path=database database 2>/dev/null \
  && echo "    Database engine enabled" || echo "    Database engine already enabled"

echo "==> 3. Configuring PostgreSQL 18.4 database connection (database/config/${PG_DB})..."
vexec vault write "database/config/${PG_DB}" \
  plugin_name="postgresql-database-plugin" \
  connection_url="postgresql://{{username}}:{{password}}@${PG_HOST}:${PG_PORT}/${PG_DB}?sslmode=disable" \
  allowed_roles="payments-app,payments-app-prod" \
  username="${PG_ADMIN_USER}" \
  password="${PG_ADMIN_PASS}"

echo "==> 4. Creating Demo DB Role database/roles/payments-app (default_ttl=1m, max_ttl=2m)..."
vexec vault write database/roles/payments-app \
  db_name="${PG_DB}" \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON payments TO \"{{name}}\";" \
  default_ttl="1m" \
  max_ttl="2m"

echo "==> 5. Creating Production DB Role database/roles/payments-app-prod (default_ttl=1h, max_ttl=24h)..."
vexec vault write database/roles/payments-app-prod \
  db_name="${PG_DB}" \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON payments TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

echo "==> 6. Writing Least-Privilege Policy 'payments-app-policy'..."
cat <<'EOF' | kubectl exec -i -n "${VAULT_NS}" "${VAULT_POD}" -- env VAULT_TOKEN="${VAULT_TOKEN}" vault policy write payments-app-policy -
path "database/creds/payments-app" {
  capabilities = ["read"]
}
path "database/creds/payments-app-prod" {
  capabilities = ["read"]
}
path "sys/leases/revoke" {
  capabilities = ["update"]
}
EOF

echo "==> 7. Configuring Secret-Less Kubernetes Auth (auth/kubernetes)..."
vexec vault auth enable kubernetes 2>/dev/null \
  && echo "    Kubernetes auth enabled" || echo "    Kubernetes auth already enabled"

vexec vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

vexec vault write auth/kubernetes/role/payments-app \
  bound_service_account_names=vault-dynamic-secrets \
  bound_service_account_namespaces=default \
  policies=payments-app-policy \
  ttl=1h

echo "==> 8. Configuring AppRole Auth (auth/approle fallback)..."
vexec vault auth enable approle 2>/dev/null \
  && echo "    AppRole auth enabled" || echo "    AppRole auth already enabled"

vexec vault write auth/approle/role/payments-app \
  token_policies="payments-app-policy" \
  token_ttl=1h token_max_ttl=4h secret_id_ttl=0

ROLE_ID=$(vexec vault read -field=role_id auth/approle/role/payments-app/role-id)
SECRET_ID=$(vexec vault write -f -field=secret_id auth/approle/role/payments-app/secret-id)

echo "=============================================================================="
echo " ✅ Vault Production Setup Complete on Kubernetes / Floci EKS!"
echo " Audit Log Device : /vault/data/vault_audit.log"
echo " Demo DB Role     : database/roles/payments-app      (TTL: 1m / 2m)"
echo " Production DB Role: database/roles/payments-app-prod (TTL: 1h / 24h)"
echo " Kubernetes Auth  : role 'payments-app' (bound to ServiceAccount vault-dynamic-secrets)"
echo " AppRole Auth     : Role ID: ${ROLE_ID}"
echo "                    Secret ID: ${SECRET_ID}"
echo "=============================================================================="
