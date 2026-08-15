#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# Script: scripts/k8s-vault-setup.sh
# Purpose: Configures HashiCorp Vault on Kubernetes for vault-dynamic-secrets
#          - Enables Database secrets engine & connects to PostgreSQL 18.4
#          - Creates dynamic role 'payments-app'
#          - Creates least-privilege policy 'payments-app-policy'
#          - Configures AppRole auth & generates Role ID / Secret ID
# ==============================================================================

VAULT_POD="${VAULT_POD:-vault-0}"
VAULT_NS="${VAULT_NS:-vault}"
PG_HOST="${PG_HOST:-postgres.default.svc.cluster.local}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-payments}"
PG_ADMIN_USER="${PG_ADMIN_USER:-postgres}"
PG_ADMIN_PASS="${PG_ADMIN_PASS:-postgres}"

echo "==> 1. Ensuring database secrets engine is enabled in Vault..."
kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- vault secrets enable -path=database database 2>/dev/null \
  && echo "    database engine enabled" || echo "    database engine already enabled"

echo "==> 2. Configuring PostgreSQL 18.4 database connection (database/config/${PG_DB})..."
kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- vault write "database/config/${PG_DB}" \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@${PG_HOST}:${PG_PORT}/${PG_DB}?sslmode=disable" \
  allowed_roles="payments-app" \
  username="${PG_ADMIN_USER}" \
  password="${PG_ADMIN_PASS}"

echo "==> 3. Creating dynamic role database/roles/payments-app (default_ttl=1m, max_ttl=2m)..."
kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- vault write database/roles/payments-app \
  db_name="${PG_DB}" \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON payments TO \"{{name}}\";" \
  default_ttl="1m" \
  max_ttl="2m"

echo "==> 4. Writing least-privilege policy 'payments-app-policy'..."
cat <<'EOF' | kubectl exec -i -n "${VAULT_NS}" "${VAULT_POD}" -- vault policy write payments-app-policy -
path "database/creds/payments-app" {
  capabilities = ["read"]
}
path "sys/leases/revoke" {
  capabilities = ["update"]
}
EOF

echo "==> 5. Enabling AppRole auth & configuring role 'payments-app'..."
kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- vault auth enable approle 2>/dev/null \
  && echo "    approle enabled" || echo "    approle already enabled"

kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- vault write auth/approle/role/payments-app \
  token_policies="payments-app-policy" \
  token_ttl=1h token_max_ttl=4h secret_id_ttl=0

ROLE_ID=$(kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- vault read -field=role_id auth/approle/role/payments-app/role-id)
SECRET_ID=$(kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- vault write -f -field=secret_id auth/approle/role/payments-app/secret-id)

echo "=============================================================================="
echo " Vault Setup Complete for Kubernetes / Floci EKS!"
echo " AppRole Role ID   : ${ROLE_ID}"
echo " AppRole Secret ID : ${SECRET_ID}"
echo "=============================================================================="
