package com.hashicorp.vaultdynamicsecrets.config;

import com.zaxxer.hikari.HikariDataSource;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.vault.core.lease.SecretLeaseContainer;
import org.springframework.vault.core.lease.event.SecretLeaseCreatedEvent;
import org.springframework.vault.core.lease.event.SecretLeaseExpiredEvent;

import static org.springframework.vault.core.lease.domain.RequestedSecret.Mode.RENEW;
import static org.springframework.vault.core.lease.domain.RequestedSecret.Mode.ROTATE;

/**
 * Alternative credential-rotation strategy: instead of rebuilding the whole
 * {@code @RefreshScope} DataSource via a context refresh (see
 * {@link VaultRefresher}), this hot-swaps the username/password directly on the
 * live HikariCP pool and soft-evicts idle connections.
 */
@Configuration
@ConditionalOnProperty(name = "app.vault.rotation-strategy", havingValue = "mxbean")
public class HikariCredentialRotator {

    HikariCredentialRotator(@Value("${spring.cloud.vault.database.role}") String databaseRole,
                            @Value("${spring.cloud.vault.database.backend}") String databaseBackend,
                            SecretLeaseContainer leaseContainer,
                            HikariDataSource hikariDataSource) {

        final Log log = LogFactory.getLog(getClass());
        final String credsPath = String.format("%s/creds/%s", databaseBackend, databaseRole);

        leaseContainer.addLeaseListener(event -> {
            if (!credsPath.equals(event.getSource().getPath())) {
                return;
            }

            if (event instanceof SecretLeaseExpiredEvent && event.getSource().getMode() == RENEW) {
                // The renewable lease reached max_ttl and can't be renewed. Switch the
                // requested secret to ROTATE so the next event carries a brand-new credential.
                log.info("⚠️ [VAULT LEASE EXPIRED] Lease expired for " + credsPath + " — switching RENEW -> ROTATE to mint fresh credentials");
                leaseContainer.requestRotatingSecret(credsPath);
            } else if (event instanceof SecretLeaseCreatedEvent created
                    && event.getSource().getMode() == ROTATE) {
                var secrets = created.getSecrets();
                var username = (String) secrets.get("username");
                var password = (String) secrets.get("password");
                // Push the new credential onto the live pool and drain idle connections.
                // Log the username only — NEVER the password (secrets must not reach logs).
                hikariDataSource.getHikariConfigMXBean().setUsername(username);
                hikariDataSource.getHikariConfigMXBean().setPassword(password);
                hikariDataSource.getHikariPoolMXBean().softEvictConnections();
                log.info("🔄 [HIKARICP MXBEAN ROTATION] >>> Live DataSource user hot-swapped to: " + username
                        + " (Soft-evicted idle pool connections, zero context teardown)");
            }
        });
    }
}
