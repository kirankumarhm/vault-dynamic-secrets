#!/usr/bin/env bash
set -Eeuo pipefail

# Build (if needed) and run the app with Vault AppRole auth.
cd "$(dirname "$0")"

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_BIN="../vault"

# role_id is stable; read it from vault.env (written by scripts/vault-setup.sh).
if [[ -f vault.env ]]; then
  set -a; source vault.env; set +a
else
  echo "vault.env not found — run ./scripts/vault-setup.sh first." >&2
  exit 1
fi

# The AppRole secret_id_ttl is very short (1m), so mint a FRESH secret_id right
# before launch. Uses your admin token (~/.vault-token) to generate it.
export VAULT_TOKEN="${VAULT_TOKEN:-$(cat ~/.vault-token)}"
echo "Minting a fresh secret_id (secret_id_ttl=1m)..."
export VAULT_APPROLE_SECRET_ID="$(${VAULT_BIN} write -f -field=secret_id auth/approle/role/payments-app/secret-id)"
# Don't leave the admin token in the app's environment.
unset VAULT_TOKEN

JAR="target/vault-dynamic-secrets-0.0.1-SNAPSHOT.jar"
[[ -f "$JAR" ]] || mvn -q -DskipTests clean package

# Checklist #13-#17,#20: production JVM flags — G1GC, bounded metaspace, heap dump
# on OOM, and fail-fast on OOM so an orchestrator can restart a healthy instance.
# In a container, also set -Xms/-Xmx to ~75% of the memory limit (left commented
# here since this is a local demo and the JVM sizes to the host by default).
JAVA_OPTS="${JAVA_OPTS:-} \
  -XX:+UseG1GC \
  -XX:MaxMetaspaceSize=256m \
  -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=./heapdump.hprof \
  -XX:+ExitOnOutOfMemoryError"
# Example container heap sizing (uncomment and tune to the container limit):
# JAVA_OPTS="$JAVA_OPTS -Xms1536m -Xmx1536m"

echo "Starting on http://localhost:8080  (AppRole role_id=${VAULT_APPROLE_ROLE_ID:0:8}…)"
exec java $JAVA_OPTS -jar "$JAR"
