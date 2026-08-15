# Production HashiCorp Vault HA & Dynamic Database Credentials on Floci EKS

This guide details how to run a production-ready **HashiCorp Vault HA (3-Node Raft Cluster with AWS KMS Auto-Unseal)** on **Kubernetes (Floci EKS emulator)**, connecting to **PostgreSQL 18.4**, and dynamically managing database credentials with zero downtime for the **`vault-dynamic-secrets`** Spring Boot 4 application.

---

## 1. Architecture Overview

```mermaid
graph TB
    subgraph Floci["Floci AWS Emulator (Local AWS Cloud)"]
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
            
            V0 --- V1
            V1 --- V2
            V2 --- V0
            V0 --> VSVC
            V1 --> VSVC
            V2 --> VSVC
        end

        subgraph DefaultNS["Namespace: default"]
            PG["PostgreSQL 18.4<br/>Service: postgres:5432<br/>Database: payments"]
            App["Spring Boot 4 Application<br/>(vault-dynamic-secrets)<br/>@RefreshScope / HikariCP"]
            AppSvc["Service: vault-dynamic-secrets<br/>Port: 8080"]
            
            App --> AppSvc
        end
    end

    V0 -->|Seal / Unseal KMS API| KMS
    VSVC -->|Dynamic DB Engine| PG
    App -->|AppRole Auth & Lease Management| VSVC
    App -->|JDBC with Ephemeral User| PG

    classDef floci fill:#ff9900,stroke:#232f3e,color:#fff
    classDef vault fill:#000,stroke:#ffd814,color:#fff
    classDef k8s fill:#326ce5,stroke:#fff,color:#fff
    classDef app fill:#6db33f,stroke:#2b6b2b,color:#fff
    classDef pg fill:#336791,stroke:#1b3a54,color:#fff

    class KMS,S3,IAM floci
    class V0,V1,V2,VSVC vault
    class App,AppSvc app
    class PG pg
```

---

## 2. Floci AWS Emulator Setup

Floci simulates AWS cloud services locally. For Vault HA, we utilize:
- **AWS KMS**: Provides envelope encryption for Vault auto-unseal (no manual unseal keys needed).
- **AWS S3**: Backup bucket for Raft snapshots (`vault-backups`).
- **AWS IAM**: Programmatic access credentials (`AKIAIOSFODNN7EXAMPLE` / `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`).

### Creating KMS Key & S3 Bucket in Floci:
```bash
# 1. Create KMS Key for Auto-Unseal
KMS_KEY_ID=$(aws --endpoint-url=http://localhost:4566 kms create-key \
  --description "Vault Auto-Unseal Key" \
  --query "KeyMetadata.KeyId" --output text)

# 2. Create S3 Bucket for Backups
aws --endpoint-url=http://localhost:4566 s3 mb s3://vault-backups
```

### Floci In-Cluster Networking Note:
Within Kubernetes pods, `localhost` points to the pod itself. The Docker bridge IP of Floci (typically `http://172.20.0.2:4566`) is injected into Vault as `FLOCI_POD_ENDPOINT` so pods can access the KMS auto-unseal endpoint seamlessly.

---

## 3. HashiCorp Vault 3-Node Raft HA Deployment

### TLS & Certificate Authority
Vault communicates securely over mTLS. A Kubernetes Secret `vault-tls` contains:
- `ca.crt`: Custom CA certificate
- `vault.crt`: Server certificate with SANs (`vault`, `vault.vault`, `vault.vault.svc.cluster.local`, `*.vault-internal`)
- `vault.key`: Private key

### Deploying Vault with Helm:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  -f vault-production-floci.yaml
```

### Initializing Vault (First Time Only):
```bash
kubectl exec -n vault vault-0 -- vault operator init \
  -ca-cert=/vault/userconfig/vault-tls/ca.crt \
  -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json

ROOT_TOKEN=$(jq -r '.root_token' cluster-keys.json)
```

Because AWS KMS Auto-Unseal is configured, all 3 nodes (`vault-0`, `vault-1`, `vault-2`) automatically unseal upon startup!

---

## 4. PostgreSQL 18.4 Infrastructure

Deploy PostgreSQL 18.4 in the `default` namespace:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:18.4
          env:
            - name: POSTGRES_DB
              value: payments
            - name: POSTGRES_USER
              value: postgres
            - name: POSTGRES_PASSWORD
              value: postgres
          ports:
            - containerPort: 5432
```

Initialize the table schema:
```bash
kubectl exec -i deployment/postgres -n default -- psql -U postgres -d payments < scripts/schema.sql
```

---

## 5. Configuring Dynamic Database Secrets in Vault

Run the automated provisioning script:
```bash
./scripts/k8s-vault-setup.sh
```

This performs:
1. **Enables Database Engine**: `database/`
2. **Configures DB Connection**: `database/config/payments` targeting `postgres.default.svc.cluster.local:5432/payments`.
3. **Creates Dynamic Role**: `database/roles/payments-app` with creation statement:
   ```sql
   CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
   GRANT ALL PRIVILEGES ON payments TO "{{name}}";
   ```
4. **Creates AppRole & Least-Privilege Policy**:
   ```hcl
   path "database/creds/payments-app" {
     capabilities = ["read"]
   }
   path "sys/leases/revoke" {
     capabilities = ["update"]
   }
   ```

---

## 6. Spring Boot 4 Application Deployment

### TLS Truststore Setup:
Because Vault uses custom TLS certificates, Java requires a JKS truststore:
```bash
keytool -import -trustcacerts -noprompt -alias vault-ca \
  -file ca.crt -keystore vault-truststore.jks -storepass changeit

kubectl create secret generic vault-truststore \
  --from-file=vault-truststore.jks=vault-truststore.jks -n default
```

### Deploying the App:
```bash
# Build Docker image and import into cluster
mvn clean package -DskipTests
docker build -t vault-dynamic-secrets:latest .
docker save vault-dynamic-secrets:latest | docker exec -i floci-eks-vault-floci ctr -n k8s.io images import -

# Apply Kubernetes manifest
kubectl apply -f k8s/deployment.yaml
```

---

## 7. Real-Time Dynamic Credential Rotation Logging

The application includes real-time logging and scheduled heartbeats to verify rotations:

### Pod Startup & First Lease Issuance:
```text
INFO --- [main] c.h.v.c.DataSourceConfig$$SpringCGLIB$$0 : 🔄 [DATASOURCE REBUILT] >>> Active Database User: v-approle-payments-PRpmyAaVJ9nwCfPErVb2-1786807932 (JDBC URL: jdbc:postgresql://postgres.default.svc.cluster.local:5432/payments)
INFO --- [main] com.zaxxer.hikari.HikariDataSource       : HikariPool-1 - Starting...
INFO --- [main] com.zaxxer.hikari.pool.HikariPool        : HikariPool-1 - Added connection org.postgresql.jdbc.PgConnection@441762b8
INFO --- [main] com.zaxxer.hikari.HikariDataSource       : HikariPool-1 - Start completed.
INFO --- [main] c.h.v.VaultDynamicSecretsApplication     : Started VaultDynamicSecretsApplication in 5.236 seconds
INFO --- [scheduling-1] c.h.v.service.CredentialRotationLogger   : 🔐 [VAULT DYNAMIC CREDS] Initial Active PostgreSQL User: v-approle-payments-PRpmyAaVJ9nwCfPErVb2-1786807932 (DB: payments)
```

### Background Heartbeat (Every 15s):
```text
INFO --- [scheduling-1] c.h.v.service.CredentialRotationLogger   : ⚡ [DB HEARTBEAT] Active PostgreSQL User: v-approle-payments-PRpmyAaVJ9nwCfPErVb2-1786807932
```

### Lease Expiry & Hot Swap (Zero-Downtime):
```text
INFO --- [g-Cloud-Vault-2] c.h.v.c.VaultRefresher$$SpringCGLIB$$0   : ⚠️ [VAULT LEASE EXPIRED] Lease database/creds/payments-app/... reached max TTL and expired! Triggering @RefreshScope Context Refresh...
INFO --- [g-Cloud-Vault-2] c.h.v.c.VaultRefresher$$SpringCGLIB$$0   : 🔐 [VAULT LEASE CREATED] Initial dynamic credential issued: v-approle-payments-G9B8uv2aI06QInyayYXh-1786808032 | Lease ID: database/creds/payments-app/... | TTL: PT1Ms
INFO --- [g-Cloud-Vault-2] com.zaxxer.hikari.HikariDataSource       : HikariPool-1 - Shutdown initiated...
INFO --- [g-Cloud-Vault-2] com.zaxxer.hikari.HikariDataSource       : HikariPool-1 - Shutdown completed.
INFO --- [g-Cloud-Vault-2] c.h.v.c.VaultRefresher$$SpringCGLIB$$0   : ✅ [CONTEXT REFRESHED] Database credentials refreshed for database/creds/payments-app

INFO --- [scheduling-1] c.h.v.c.DataSourceConfig$$SpringCGLIB$$0 : 🔄 [DATASOURCE REBUILT] >>> Active Database User: v-approle-payments-G9B8uv2aI06QInyayYXh-1786808032 (JDBC URL: jdbc:postgresql://postgres.default.svc.cluster.local:5432/payments)
INFO --- [scheduling-1] com.zaxxer.hikari.HikariDataSource       : HikariPool-2 - Starting...
INFO --- [scheduling-1] com.zaxxer.hikari.pool.HikariPool        : HikariPool-2 - Added connection org.postgresql.jdbc.PgConnection@6b875168
INFO --- [scheduling-1] com.zaxxer.hikari.HikariDataSource       : HikariPool-2 - Start completed.
INFO --- [scheduling-1] c.h.v.service.CredentialRotationLogger   : 🔄 [VAULT DYNAMIC CREDS ROTATION DETECTED] >>> Previous User: v-approle-payments-PRpmyAaVJ9nwCfPErVb2-1786807932 -> NEW Active User: v-approle-payments-G9B8uv2aI06QInyayYXh-1786808032 <<< (Zero-downtime rotation verified!)
```

---

## 8. Verification & Testing

### Test HTTP Endpoints:
```bash
kubectl port-forward svc/vault-dynamic-secrets 8080:8080 -n default &

# 1. Create a payment
curl -X POST http://localhost:8080/payments \
  -H "Content-Type: application/json" \
  -d '{"name": "Jane Doe", "cc_info": "4111-2222-3333-4444"}'

# 2. Check dynamic database status & active user
curl -s http://localhost:8080/payments/db-status | jq .

# 3. List payments
curl -s http://localhost:8080/payments | jq .
```

### Inspect PostgreSQL Roles:
```bash
kubectl exec -it deployment/postgres -n default -- psql -U postgres -d payments -c "\du"
```
Notice that old roles are dropped automatically upon lease expiration by Vault!
