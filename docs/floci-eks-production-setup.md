# Production HashiCorp Vault HA, Dynamic Database Secrets, Secret-Less Kubernetes Auth & Distributed Tracing on Floci EKS

This guide is an end-to-end, production-grade runbook for deploying a highly secure, observable, zero-downtime microservices stack on **Kubernetes (Floci EKS emulator)**:
- **HashiCorp Vault HA**: 3-Node Raft Cluster with AWS KMS Auto-Unseal & File Audit Logging.
- **Secret-Less Kubernetes Authentication**: Pods authenticate to Vault using native Kubernetes ServiceAccount JWT tokens (zero static secrets at rest).
- **PostgreSQL 18.4 Dynamic Secrets**: Ephemeral database users minted on demand and hot-swapped inside the JVM via Spring Cloud Vault.
- **Observability & Traceability**: OpenTelemetry distributed tracing exported to **Jaeger** and Prometheus metrics via Spring Boot Actuator.

---

## 1. Complete Architecture Diagram

```mermaid
graph TB
    subgraph Floci["Floci AWS Emulator (Local AWS Cloud :4566)"]
        KMS["AWS KMS Key<br/>(Auto-Unseal Provider)"]
        S3["AWS S3 Bucket<br/>(vault-backups)"]
        IAM["AWS IAM User<br/>(vault-autounseal)"]
    end

    subgraph K8s["Kubernetes Cluster (Floci EKS / k3s)"]
        subgraph VaultNS["Namespace: vault"]
            V0["vault-0 (Leader)<br/>Raft Storage + TLS"]
            V1["vault-1 (Follower)<br/>Raft Storage + TLS"]
            V2["vault-2 (Follower)<br/>Raft Storage + TLS"]
            VSVC["Service: vault<br/>vault.vault.svc:8200"]
            AuditLog[("/vault/data/vault_audit.log<br/>HMAC Cryptographic Audit")]
            
            V0 --- V1
            V1 --- V2
            V2 --- V0
            V0 --> VSVC
            V1 --> VSVC
            V2 --> VSVC
            V0 --> AuditLog
        end

        subgraph DefaultNS["Namespace: default"]
            SA["ServiceAccount:<br/>vault-dynamic-secrets"]
            App["Spring Boot 4 Application<br/>(vault-dynamic-secrets)<br/>@RefreshScope / HikariCP Pool"]
            AppSvc["Service: vault-dynamic-secrets<br/>Port: 8080"]
            PG["PostgreSQL 18.4<br/>Service: postgres:5432<br/>Database: payments"]
            Jaeger["Jaeger Distributed Tracing<br/>OTLP :4318 / UI :16686"]
            
            SA --> App
            App --> AppSvc
            App -->|OTLP Traces| Jaeger
        end
    end

    V0 -->|Seal / Unseal KMS API| KMS
    VSVC -->|Dynamic DB Engine| PG
    App -->|1. Authenticate with SA JWT Token| VSVC
    VSVC -->|2. Mint Ephemeral User| PG
    App -->|3. JDBC Connection with Ephemeral User| PG

    classDef floci fill:#ff9900,stroke:#232f3e,color:#fff
    classDef vault fill:#000,stroke:#ffd814,color:#fff
    classDef k8s fill:#326ce5,stroke:#fff,color:#fff
    classDef app fill:#6db33f,stroke:#2b6b2b,color:#fff
    classDef pg fill:#336791,stroke:#1b3a54,color:#fff
    classDef obs fill:#6025e6,stroke:#fff,color:#fff

    class KMS,S3,IAM floci
    class V0,V1,V2,VSVC,AuditLog vault
    class App,AppSvc,SA app
    class PG pg
    class Jaeger obs
```

---

## 2. Step-by-Step Production Setup

### Step 1: Floci AWS Emulator & KMS Auto-Unseal Key
Ensure Floci is running locally (`http://localhost:4566`):
```bash
# 1. Create KMS Key for Vault Auto-Unseal
KMS_KEY_ID=$(aws --endpoint-url=http://localhost:4566 kms create-key \
  --description "Vault Auto-Unseal Key" \
  --query "KeyMetadata.KeyId" --output text)

# 2. Create S3 Bucket for Raft Backups
aws --endpoint-url=http://localhost:4566 s3 mb s3://vault-backups
```

---

### Step 2: Deploy HashiCorp Vault 3-Node Raft HA Cluster
1. **Generate Custom CA & Server TLS Certificates**:
   ```bash
   # Create TLS certificates with SANs for internal cluster communication
   openssl req -x509 -newkey rsa:4096 -days 365 -nodes \
     -keyout tls/ca.key -out tls/ca.crt -subj "/CN=Vault-Internal-CA"

   openssl req -newkey rsa:2048 -nodes \
     -keyout tls/vault.key -out tls/vault.csr \
     -subj "/CN=vault.vault.svc.cluster.local"

   openssl x509 -req -in tls/vault.csr -CA tls/ca.crt -CAkey tls/ca.key \
     -CAcreateserial -out tls/vault.crt -days 365 \
     -extfile <(printf "subjectAltName=DNS:vault,DNS:vault.vault,DNS:vault.vault.svc.cluster.local,DNS:*.vault-internal,IP:127.0.0.1")

   # Create Kubernetes secret
   kubectl create namespace vault
   kubectl create secret generic vault-tls -n vault \
     --from-file=ca.crt=tls/ca.crt \
     --from-file=vault.crt=tls/vault.crt \
     --from-file=vault.key=tls/vault.key
   ```

2. **Deploy Vault Helm Chart with Auto-Unseal**:
   ```bash
   helm repo add hashicorp https://helm.releases.hashicorp.com
   helm repo update

   helm upgrade --install vault hashicorp/vault \
     --namespace vault \
     -f vault-production-floci.yaml
   ```

3. **Initialize Vault (First Time Only)**:
   ```bash
   kubectl exec -n vault vault-0 -- vault operator init \
     -ca-cert=/vault/userconfig/vault-tls/ca.crt \
     -key-shares=1 -key-threshold=1 -format=json > vault-init.json

   ROOT_TOKEN=$(jq -r '.root_token' vault-init.json)
   ```

---

### Step 3: Deploy PostgreSQL 18.4
Deploy PostgreSQL 18.4 in the `default` namespace:
```bash
kubectl apply -f postgres-deployment.yaml

# Wait for PostgreSQL to be ready and initialize the payments schema
kubectl exec -i deployment/postgres -n default -- psql -U postgres -d payments < scripts/schema.sql
```

---

### Step 4: Deploy Jaeger Distributed Tracing
Deploy Jaeger All-In-One to collect and visualize OpenTelemetry traces:
```bash
kubectl apply -f k8s/jaeger-deployment.yaml
```

---

### Step 5: Configure Vault with Secret-Less Kubernetes Auth & Dynamic DB Engine
Run the automated configuration script:
```bash
./scripts/k8s-vault-setup.sh
```

What this script automates:
1. **Enables Audit Logging**: Cryptographic logging to `/vault/data/vault_audit.log`.
2. **Configures Database Engine**: Connects `database/config/payments` to `postgres.default.svc.cluster.local:5432/payments`.
3. **Creates Dynamic DB Role**: `payments-app` with 1m default / 2m max TTL.
4. **Enables Kubernetes Auth (`auth/kubernetes`)**: Points to `https://kubernetes.default.svc:443`.
5. **Binds ServiceAccount**: Maps ServiceAccount `vault-dynamic-secrets` in namespace `default` to policy `payments-app-policy`.

---

### Step 6: Create Java TLS Truststore & Deploy Application
1. **Generate JKS Truststore for Spring Boot**:
   ```bash
   keytool -import -trustcacerts -noprompt -alias vault-ca \
     -file tls/ca.crt -keystore tls/vault-truststore.jks -storepass changeit

   kubectl create secret generic vault-truststore \
     --from-file=vault-truststore.jks=tls/vault-truststore.jks -n default
   ```

2. **Build and Load Docker Image into Cluster**:
   ```bash
   mvn clean package -DskipTests
   docker build -t vault-dynamic-secrets:latest .
   docker save vault-dynamic-secrets:latest | docker exec -i floci-eks-vault-floci ctr -n k8s.io images import -
   ```

3. **Apply Kubernetes Deployment**:
   ```bash
   kubectl apply -f k8s/deployment.yaml
   ```

---

## 3. Secret-Less Kubernetes Authentication vs. AppRole

| Feature | Kubernetes Native Auth *(Active)* | AppRole Auth *(Fallback)* |
|---|---|---|
| **Credential Type** | Pod's projected ServiceAccount token (`/var/run/secrets/...`) | Static `role_id` and `secret_id` |
| **Secret Storage at Rest** | **Zero stored secret**: Token is short-lived and auto-rotated by Kubernetes. | `secret_id` stored in Kubernetes `Secret` object. |
| **Revocation on Pod Delete** | Instant: Token becomes invalid as soon as pod is terminated. | Requires explicit lease revocation. |
| **Configuration** | `spring.cloud.vault.authentication=KUBERNETES` | `spring.cloud.vault.authentication=APPROLE` |

---

## 4. Production TTL Tuning vs. Demo TTL Tuning

To change from Demo TTL (1m/2m) to Production TTL (1h/24h):

### Demo Profile (Default):
- `default_ttl`: `1m`, `max_ttl`: `2m`
- `min-renewal`: `30s`, `expiry-threshold`: `10s`
- `spring.datasource.hikari.max-lifetime`: `90s`

### Production Profile (`SPRING_PROFILES_ACTIVE=prod`):
- `default_ttl`: `1h`, `max_ttl`: `24h`
- `min-renewal`: `15m`, `expiry-threshold`: `5m`
- `spring.datasource.hikari.max-lifetime`: `45m` (`2700000ms`)
- `spring.datasource.hikari.maximum-pool-size`: `50`

To activate production settings in Kubernetes, set `SPRING_PROFILES_ACTIVE: "prod"` in `vault-dynamic-secrets-config` ConfigMap.

---

## 5. Observability, Telemetry & Tracing Runbook

### 1. View Live Dynamic Credential Telemetry (`/actuator/vaultLease`):
```bash
kubectl port-forward svc/vault-dynamic-secrets 8080:8080 -n default &
curl -s http://localhost:8080/actuator/vaultLease | jq .
```
Output:
```json
{
  "activeDatabaseUser": "v-kubernet-payments-yhjMjurqBDjvLG1pC1C8-1786809984",
  "role": "payments-app",
  "rotationStrategy": "refresh-scope",
  "lastRotationTime": "2026-08-15T16:06:24.919Z",
  "backend": "database",
  "rotationCount": 1,
  "status": "ACTIVE"
}
```

### 2. View Distributed Tracing in Jaeger UI:
```bash
kubectl port-forward svc/jaeger 16686:16686 -n default &
```
Open **`http://localhost:16686`** in your browser to inspect end-to-end trace spans for HTTP controllers, Spring Data JPA repositories, and JDBC executions with latency metrics.

### 3. View Real-Time Dynamic Rotation Logs:
```bash
kubectl logs -l app=vault-dynamic-secrets -n default -f
```
Observe the automated heartbeat detecting and logging rotations:
```text
INFO [vault-dynamic-secrets,traceId,spanId] : ⚡ [DB HEARTBEAT] Active PostgreSQL User: v-kubernet-payments-x95uvo1nWjKRLvIPXLjU-1786809884
INFO [vault-dynamic-secrets,traceId,spanId] : ⚠️ [VAULT LEASE EXPIRED] Lease expired! Triggering @RefreshScope Context Refresh...
INFO [vault-dynamic-secrets,traceId,spanId] : 🔄 [DATASOURCE REBUILT] >>> Active Database User: v-kubernet-payments-yhjMjurqBDjvLG1pC1C8-1786809984
INFO [vault-dynamic-secrets,traceId,spanId] : 🔄 [VAULT DYNAMIC CREDS ROTATION DETECTED] >>> Previous User: v-kubernet-... -> NEW Active User: v-kubernet-... <<<
```

### 4. Inspect Vault Audit Log:
```bash
kubectl exec -n vault vault-0 -- tail -f /vault/data/vault_audit.log
```
Every token login, dynamic secret lease issuance, and revocation is recorded with cryptographic HMAC hashing.
