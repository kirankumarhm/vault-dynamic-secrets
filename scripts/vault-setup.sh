#!/usr/bin/env bash
set -Eeuo pipefail

# Configure Vault's database secrets engine for the payments demo — the local,
# no-Docker equivalent of the repo's reload/scripts/vault.sh, adapted to a
# natively-running Vault + Postgres.
#
# Matches the video: role "payments-app", short TTLs (1m default / 2m max) so
# credential rotation is easy to watch. The app authenticates with a Vault
# TOKEN (spring.cloud.vault.token), so no policy/AppRole is needed here.
#
# Requires: Vault running & unsealed, logged in as root/admin (~/.vault-token),
# and Postgres reachable with the admin creds below.

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_HOME="${VAULT_HOME:-/Users/2337057/Applications/HashiCorp/vault}"
VAULT="${VAULT_HOME}/vault"

# Postgres admin account Vault uses ONLY to create/drop the dynamic users.
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-payments}"
PG_ADMIN_USER="${PG_ADMIN_USER:-postgres}"
PG_ADMIN_PASS="${PG_ADMIN_PASS:-postgres}"

echo "==> Ensuring the database secrets engine is enabled"
$VAULT secrets enable -path=database database 2>/dev/null \
  && echo "    enabled" || echo "    already enabled"

echo "==> Configuring connection database/config/${PG_DB}"
$VAULT write "database/config/${PG_DB}" \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@${PG_HOST}:${PG_PORT}/${PG_DB}" \
  allowed_roles="payments-app" \
  username="${PG_ADMIN_USER}" \
  password="${PG_ADMIN_PASS}" >/dev/null
echo "    done"

echo "==> Creating role database/roles/payments-app (default_ttl=1m, max_ttl=2m)"
$VAULT write database/roles/payments-app \
  db_name="${PG_DB}" \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON payments TO \"{{name}}\";" \
  default_ttl="1m" \
  max_ttl="2m" >/dev/null
echo "    done"

echo "==> Writing least-privilege policy 'payments-app-policy'"
$VAULT policy write payments-app-policy - <<'EOF'
# The app may request dynamic DB credentials...
path "database/creds/payments-app" {
  capabilities = ["read"]
}
# ...and revoke its own lease on shutdown (Spring Cloud Vault calls sys/leases/revoke),
# so the ephemeral Postgres user is dropped immediately instead of lingering to TTL.
path "sys/leases/revoke" {
  capabilities = ["update"]
}
EOF
echo "    done"

echo "==> Enabling AppRole auth + role 'payments-app'"
$VAULT auth enable approle 2>/dev/null && echo "    enabled" || echo "    already enabled"
# secret_id_ttl is intentionally short (1m); run.sh mints a fresh secret_id at
# each launch so this tiny TTL never bites. token_ttl (1h) keeps the running app
# authenticated without needing the secret_id again.
$VAULT write auth/approle/role/payments-app \
  token_policies="payments-app-policy" \
  token_ttl=1h token_max_ttl=4h secret_id_ttl=1m >/dev/null
echo "    done"

echo "==> Writing AppRole credentials to vault.env (chmod 600, gitignored)"
ROLE_ID="$($VAULT read -field=role_id auth/approle/role/payments-app/role-id)"
SECRET_ID="$($VAULT write -f -field=secret_id auth/approle/role/payments-app/secret-id)"
ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/vault.env"
cat >"${ENV_FILE}" <<EOF
# AppRole credentials for vault-dynamic-secrets — DO NOT COMMIT.
export VAULT_APPROLE_ROLE_ID="${ROLE_ID}"
export VAULT_APPROLE_SECRET_ID="${SECRET_ID}"
EOF
chmod 600 "${ENV_FILE}"
echo "    wrote ${ENV_FILE}"

echo
echo "Vault is configured (AppRole auth). Verify dynamic creds:"
echo "  ${VAULT} read database/creds/payments-app"
echo
echo "Run the app (run.sh sources vault.env automatically):"
echo "  export VAULT_ADDR=${VAULT_ADDR}"
echo "  ./run.sh"
