#!/bin/sh
# Provision the dev Vault for docker-compose:
#   - PostgreSQL database secrets engine + role "payments-app"
#   - least-privilege policy + AppRole
#   - writes role_id/secret_id to the shared volume for the app to consume
#
# Runs once (compose `vault-init` service) against the compose network:
#   VAULT_ADDR=http://vault:8200, DB host=postgres. Idempotent-ish: re-enabling
# an engine that already exists is tolerated.
set -eu

export VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-root}"

APP="payments-app"
POLICY="payments-app-policy"
PG_HOST="${PG_HOST:-postgres}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-payments}"
PG_USER="${PG_USER:-postgres}"
PG_PASS="${PG_PASS:-postgres}"
SHARED="${SHARED_DIR:-/shared}"

echo "==> Waiting for Vault at ${VAULT_ADDR}"
until vault status >/dev/null 2>&1; do sleep 1; done

echo "==> Enabling database secrets engine"
vault secrets enable -path=database database 2>/dev/null || echo "    already enabled"

echo "==> Configuring PostgreSQL connection"
vault write database/config/"${PG_DB}" \
  plugin_name=postgresql-database-plugin \
  allowed_roles="${APP}" \
  connection_url="postgresql://{{username}}:{{password}}@${PG_HOST}:${PG_PORT}/${PG_DB}?sslmode=disable" \
  username="${PG_USER}" \
  password="${PG_PASS}"

echo "==> Creating dynamic role '${APP}' (production-ish TTLs)"
vault write database/roles/"${APP}" \
  db_name="${PG_DB}" \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON payments TO \"{{name}}\";" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

echo "==> Writing least-privilege policy '${POLICY}'"
vault policy write "${POLICY}" - <<EOF
path "database/creds/${APP}" { capabilities = ["read"] }
path "sys/leases/revoke"    { capabilities = ["update"] }
EOF

echo "==> Enabling AppRole and creating role '${APP}'"
vault auth enable approle 2>/dev/null || echo "    already enabled"
vault write auth/approle/role/"${APP}" \
  token_policies="${POLICY}" \
  token_ttl=1h token_max_ttl=4h secret_id_ttl=24h

ROLE_ID="$(vault read -field=role_id auth/approle/role/${APP}/role-id)"
SECRET_ID="$(vault write -f -field=secret_id auth/approle/role/${APP}/secret-id)"

mkdir -p "${SHARED}"
cat >"${SHARED}/vault.env" <<EOF
export VAULT_APPROLE_ROLE_ID="${ROLE_ID}"
export VAULT_APPROLE_SECRET_ID="${SECRET_ID}"
EOF

echo "==> Wrote AppRole credentials to ${SHARED}/vault.env"
echo "    provisioning complete."
