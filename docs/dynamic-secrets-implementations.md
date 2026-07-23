# Dynamic Secrets — Implementation Guide

"Dynamic secrets" is a **pattern**: credentials are *generated on demand*, are
*unique*, *short-lived*, and *auto-expire/revoke*. This project implements it with
**Vault database engine + Spring Cloud Vault + AppRole**. Below are the other
concrete implementations, with mechanism, moving parts, config/code, and the
credential lifecycle.

The generic pattern every implementation follows:

```text
workload ──(prove identity)──▶ broker ──(admin creds)──▶ datastore
                                  │  creates ephemeral user / short-lived token
                                  ▼
                          returns creds + lease/TTL ──▶ auto-renew ──▶ expire/revoke
```

---

## A. Same Vault database engine, different client integration

The server side is identical to this project (`database/` secrets engine, a role
with `creation_statements` + TTLs). Only *how the app receives the credential*
changes.

### A1. This project — Spring Cloud Vault (in-process)

The app is Vault-aware: Spring Cloud Vault authenticates, imports
`database/creds/<role>` as `spring.datasource.username/password`, and a
`@RefreshScope` `DataSource` is rebuilt on lease expiry.

```properties
spring.cloud.vault.authentication=APPROLE
spring.cloud.vault.database.enabled=true
spring.cloud.vault.database.role=payments-app
```

- **Pros:** no sidecar, native Spring.
- **Cons:** app coupled to Vault SDK; pool-rebuild logic; JVM-only.

### A2. Vault Agent (sidecar, language-agnostic)

A **Vault Agent** process authenticates for the app (auto-auth), renews the lease,
and **templates the credential into a file**. The app just reads the file.

`vault-agent.hcl`:

```hcl
auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "/etc/vault/role_id"
      secret_id_file_path = "/etc/vault/secret_id"
    }
  }
  sink "file" { config = { path = "/etc/vault/token" } }
}

template {
  destination = "/vault/secrets/db.properties"
  contents = <<EOT
{{ with secret "database/creds/payments-app" }}
spring.datasource.username={{ .Data.username }}
spring.datasource.password={{ .Data.password }}
{{ end }}
EOT
  command = "pkill -HUP -f payments.jar"   # signal the app to reload
}
```

App side (Spring, Vault-unaware):

```properties
spring.config.import=optional:file:/vault/secrets/db.properties
```

- **Pros:** app doesn't know Vault exists; works for any language.
- **Cons:** extra process; you handle app reload on rotation.

### A3. Vault Agent Injector (Kubernetes, annotation-driven)

A mutating webhook injects the agent sidecar automatically from pod annotations —
no sidecar YAML to write.

```yaml
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "payments-app"
        vault.hashicorp.com/agent-inject-secret-db: "database/creds/payments-app"
        vault.hashicorp.com/agent-inject-template-db: |
          {{- with secret "database/creds/payments-app" -}}
          spring.datasource.username={{ .Data.username }}
          spring.datasource.password={{ .Data.password }}
          {{- end }}
```

Secret appears at `/vault/secrets/db` inside every pod.

### A4. Vault Secrets Operator (VSO, CRD-driven)

An operator reconciles CRDs, writes the dynamic secret into a **native K8s Secret**,
and can **trigger a rolling restart** on rotation.

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata: { name: payments-db }
spec:
  mount: database
  path: creds/payments-app
  destination: { name: payments-db-secret, create: true }
  rolloutRestartTargets:
    - { kind: Deployment, name: payments }
  refreshAfter: 1h
```

App consumes it as a normal K8s Secret (`envFrom`/`secretKeyRef`).

### A5. Vault CSI provider (Secrets Store CSI Driver)

Secrets mounted as a **volume**.

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
spec:
  provider: vault
  parameters:
    roleName: payments-app
    objects: |
      - objectName: db-username
        secretPath: "database/creds/payments-app"
        secretKey: username
      - objectName: db-password
        secretPath: "database/creds/payments-app"
        secretKey: password
```

- **Caveat:** CSI mounts at pod start; rotation of dynamic creds needs the driver's
  rotation-reconciler and app reload — often A2/A4 fit dynamic creds better.

### A6. Swap the auth method (drop AppRole entirely)

The database engine is unchanged; only *how the app authenticates to Vault* changes.

| Auth method | Identity source | Spring Cloud Vault |
|---|---|---|
| **Kubernetes** | pod ServiceAccount JWT (TokenReview) | `authentication=KUBERNETES` |
| **AWS IAM** | EC2/IRSA identity | `authentication=AWS_IAM` |
| **GCP/Azure** | instance/managed identity | `authentication=GCP_IAM` / `AZURE` |
| **JWT/OIDC** | any OIDC token | `authentication=JWT` |
| **TLS cert** | client certificate | `authentication=CERT` |

Kubernetes example (no `role_id`/`secret_id` to distribute):

```bash
vault auth enable kubernetes
vault write auth/kubernetes/role/payments-app \
  bound_service_account_names=payments \
  bound_service_account_namespaces=default \
  policies=payments-app-policy ttl=1h
```

---

## B. Cloud-native IAM database authentication (no Vault, no stored password)

The database trusts a **cloud identity**; the app fetches a short-lived token and
uses it as the DB password. There is *never* a stored credential.

### B1. AWS RDS/Aurora IAM authentication

1. Enable IAM auth on the instance; create a DB user mapped to IAM:

   ```sql
   CREATE USER app_iam;              -- Postgres
   GRANT rds_iam TO app_iam;
   ```

2. IAM policy grants `rds-db:connect` on the specific db-user ARN.
3. App gets a **15-minute** token and connects over TLS. Easiest is the AWS JDBC
   wrapper driver, which regenerates tokens automatically:

   ```properties
   spring.datasource.url=jdbc:aws-wrapper:postgresql://db.xxxx.rds.amazonaws.com:5432/payments?wrapperPlugins=iam
   spring.datasource.driver-class-name=software.amazon.jdbc.Driver
   spring.datasource.username=app_iam
   # no password — the iam plugin mints a token per connection
   ```

   Manual variant: `RdsUtilities.generateAuthenticationToken(...)` → use as password.

- **Pros:** zero secret storage; AWS-native IAM audit.
- **Cons:** AWS-only; 15-min token; TLS mandatory.

### B2. GCP Cloud SQL IAM authentication

Enable the `cloudsql.iam_authentication` flag, add an IAM DB user (a service
account), and use the Cloud SQL Java Connector:

```properties
spring.datasource.url=jdbc:postgresql:///payments\
?cloudSqlInstance=proj:region:inst&socketFactory=com.google.cloud.sql.postgres.SocketFactory\
&enableIamAuth=true&sslmode=disable
spring.datasource.username=sa-name@project.iam
```

Token comes from Application Default Credentials (Workload Identity on GKE).

### B3. Azure AD authentication (Azure Database for PostgreSQL/MySQL)

A Managed Identity requests an AAD token and uses it as the password:

```java
String token = new DefaultAzureCredentialBuilder().build()
    .getToken(new TokenRequestContext()
        .addScopes("https://ossrdbms-aad.database.windows.net/.default"))
    .block().getToken();
// use `token` as the JDBC password; refresh before expiry
```

---

## C. Managed secret managers with rotation

Here the credential is a **fairly-static secret that is rotated on a schedule**
(hours/days) rather than a per-request ephemeral user — a lighter flavor of dynamic.

### C1. AWS Secrets Manager + rotation Lambda

- Secret holds `{"username","password"}`. A rotation Lambda (AWS provides RDS
  templates) rotates on a schedule using **single-user** or **alternating-users**
  strategy (the latter avoids downtime).
- App reads via SDK with a caching client, or Spring Cloud AWS:

  ```properties
  spring.config.import=aws-secretsmanager:payments/db
  ```

- **Pros:** managed, no Vault; **Cons:** rotation is periodic, not per-request; still a stored secret between rotations.

### C2. Infisical dynamic secrets

Infisical has a first-class **Dynamic Secrets** feature (this is what the sibling
`infisical-dynamic-secrets` project uses). You register a DB connection in
Infisical, define a dynamic-secret with a TTL, then lease creds via SDK/CLI/Agent:

```bash
infisical dynamic-secrets lease create --name payments-db --ttl 1h
```

The **Infisical Agent** works like Vault Agent (templates leased creds to a file).

### C3. Akeyless

SaaS with **dynamic secret producers** (DB, cloud, etc.). A lightweight Gateway
brokers creation; apps fetch via SDK/CLI. Similar model to Vault without self-hosting.

---

## D. Kubernetes sync layer

### D1. External Secrets Operator (ESO)

ESO **syncs from a backend** into a K8s Secret. Pair it with a backend that
*generates* dynamic secrets (e.g. Vault) to get the dynamic property:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: { name: payments-db }
spec:
  refreshInterval: 1h
  secretStoreRef: { name: vault-backend, kind: SecretStore }
  target: { name: payments-db-secret }
  dataFrom:
    - extract: { key: database/creds/payments-app }
```

- **Caveat:** each refresh may create a **new lease** — tune `refreshInterval` and
  understand old leases expire on their own TTL.

---

## E. Access brokers / just-in-time proxies

The credential never reaches the app as a secret — a **proxy** injects ephemeral
creds/certs per session and records a full audit.

### E1. Teleport Database Access

- Postgres trusts Teleport's CA (`clientcert`), mapping short-lived X.509 certs to
  DB users. For apps, **Machine ID (`tbot`)** issues rotating certs to a file:

  ```bash
  tbot start -c tbot.yaml    # writes short-lived DB cert + CA to /opt/machine-id
  ```
- App connects to the local Teleport proxy using those certs.
- **Pros:** per-session identity + audit, works for humans and machines.

### E2. HashiCorp Boundary / StrongDM

A brokered proxy holds the real credentials and injects them; the app connects to
`localhost:<proxy-port>` with no secret of its own. Central policy + session recording.

---

## F. Identity foundations

### F1. SPIFFE / SPIRE + certificate DB auth

- SPIRE issues short-lived **X.509 SVIDs** to workloads via the Workload API
  (auto-rotated by the SPIRE agent).
- Postgres uses `clientcert` auth trusting the SPIFFE CA; the app's identity is its
  SPIFFE ID. No password anywhere — the "secret" is a continuously-rotated cert.

---

## G. Roll-your-own broker (what Vault's DB engine does internally)

If you ever build it yourself, the trusted broker must:

1. **Authenticate the workload** (mTLS, cloud IAM, signed JWT).
2. Hold **admin DB creds** (itself stored in a secret manager).
3. `CREATE ROLE <random> LOGIN PASSWORD <random> VALID UNTIL <now+ttl>` + grants.
4. Return creds + a **lease id**; track it.
5. On expiry/revoke, `DROP ROLE` (and terminate its sessions).

This is exactly Vault's `database` engine — which is why using Vault (or a managed
equivalent) is almost always better than rebuilding it.

---

## Decision matrix

| Situation | Recommended implementation |
|---|---|
| Single cloud, managed DB | **Cloud IAM DB auth** (B) — simplest, no password, no Vault |
| Multi-cloud / on-prem / many secret types | **Vault** (A) — most engines, one control plane |
| Kubernetes, app should stay secret-unaware | Vault + **Agent Injector / VSO** (A3/A4) |
| Sync into K8s Secrets from any backend | **External Secrets Operator** (D1) |
| No infra to run | **Infisical / Akeyless** (C2/C3) |
| Human + machine JIT access with session audit | **Teleport / Boundary / StrongDM** (E) |
| Zero-password, identity-based, on-prem | **SPIFFE/SPIRE + cert auth** (F1) |
