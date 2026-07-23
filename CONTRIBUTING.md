# Contributing & Operations

Developer setup, conventions, and an operational runbook for
`vault-dynamic-secrets`. For the product overview and the dynamic-secrets
rationale, see [README.md](README.md).

## Prerequisites

| Tool | Version |
|------|---------|
| JDK | 21 |
| Maven | 3.9+ |
| Docker | any recent (only for `mvn verify` / compose) |
| PostgreSQL | 17 (local dev) |
| Vault | binary at repo root (`../vault`) |

## Build & test

```bash
mvn test        # fast: unit + web-slice (no Docker, no Vault, no DB)
mvn verify      # + Testcontainers integration test (needs Docker)
mvn -DskipTests clean package   # build the jar only
```

- **Unit** tests mock collaborators (`PaymentServiceTest`).
- **Web slice** tests use `@WebMvcTest` + MockMvc (`PaymentControllerTest`).
- **Integration** tests (`*IT`) run under failsafe against a real PostgreSQL via
  Testcontainers. Name new integration tests `*IT`; name fast tests `*Test`.

## Code layout (layered architecture)

Every class lives in exactly one layer under
`com.hashicorp.vaultdynamicsecrets`:

```
controller/  → HTTP only (thin)          service/     → business logic
repository/  → Spring Data JPA           entity/      → JPA @Entity (persistence only)
dto/         → request/response records   exception/   → error types + @RestControllerAdvice
config/      → @Configuration, rotation   filter/      → servlet filters
constants/   → shared constants
```

Rules of thumb:
- Controllers never touch the repository or the entity — go through the service,
  return DTOs (`PaymentResponse`), never the entity.
- New business logic goes in a service; keep controllers transport-only.
- Secrets must never be logged. Log the Vault-issued **username** only.

## Conventions

- Java 21, records for DTOs, constructor injection (no field `@Autowired`).
- Errors surface as RFC 7807 `application/problem+json` via
  `GlobalExceptionHandler`; throw a typed exception (e.g. `PaymentNotFoundException`).
- Keep `spring.datasource.hikari.max-lifetime` **below** the Vault role `max_ttl`.

---

## Operations runbook

### Start / stop the local stack (no containers)

```bash
../start.sh                                   # start Vault (foreground)
export VAULT_ADDR=http://127.0.0.1:8200
../vault operator unseal                      # paste the unseal key (each restart)
./scripts/vault-setup.sh                      # first time: engine, policy, AppRole
./run.sh                                       # start the app on :8080
```

Stop: Ctrl-C the app, then `../vault operator seal` (or stop the Vault process).

### Health & observability

| Endpoint | Use |
|----------|-----|
| `GET /actuator/health/liveness` | is the process alive (k8s liveness) |
| `GET /actuator/health/readiness` | can it serve traffic (k8s readiness) |
| `GET /actuator/prometheus` | metrics scrape |
| `GET /actuator/info` | build info |

### Credential rotation

Rotation strategy is set by `app.vault.rotation-strategy` (`refresh-scope` |
`mxbean`). Watch it live:

```bash
tail -f app.log | grep -iE 'Rotated datasource|Rebuilt datasource|Refreshed database credentials'
```

A different Vault-issued username on each rotation is the credential changing
under the running app. Periodic `Cannot renew lease ... lease expired` WARNs are
expected (the lease hitting `max_ttl`); the app fetches fresh creds and continues.

### Common incidents

| Symptom | Action |
|---------|--------|
| App won't start, `Vault ... Connection refused` | Start/unseal Vault; check `VAULT_ADDR`. |
| App up but DB errors | PostgreSQL down, or `payments` table missing (`scripts/schema.sql`). |
| Auth failures at startup | AppRole `secret_id` expired — `run.sh` mints a fresh one; ensure `~/.vault-token` is valid. |
| Connections killed mid-request | `max-lifetime` ≥ role `max_ttl`; lower `max-lifetime`. |
| `mvn verify` can't find Docker | Start Docker, or run `mvn test` for the Docker-free suite. |

### Rotating a leaked credential

If an AppRole `secret_id` or the DB engine root credential leaks: revoke the
AppRole secret-id (`vault write auth/approle/role/payments-app/secret-id-accessor/destroy ...`),
rotate the DB engine root password (`vault write -f database/rotate-root/payments`),
and redeploy. Active dynamic leases can be revoked in bulk with
`vault lease revoke -prefix database/creds/payments-app`.
