package com.hashicorp.vaultdynamicsecrets.config;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.cloud.context.refresh.ContextRefresher;
import org.springframework.context.annotation.Configuration;
import org.springframework.vault.core.lease.SecretLeaseContainer;
import org.springframework.vault.core.lease.event.SecretLeaseCreatedEvent;
import org.springframework.vault.core.lease.event.SecretLeaseExpiredEvent;
import org.springframework.vault.core.lease.event.SecretLeaseRotatedEvent;

/**
 * Wires a Vault lease listener: when the dynamic database credential lease
 * expires, it triggers a context refresh so the {@code @RefreshScope}
 * {@code DataSource} ({@link DataSourceConfig}) is rebuilt with fresh
 * credentials.
 *
 * This is the {@code refresh-scope} rotation strategy (the default). For the
 * lower-overhead alternative see {@link HikariCredentialRotator}.
 */
@Configuration
@ConditionalOnProperty(name = "app.vault.rotation-strategy",
        havingValue = "refresh-scope", matchIfMissing = true)
public class VaultRefresher {

    VaultRefresher(@Value("${spring.cloud.vault.database.role}") String databaseRole,
                   @Value("${spring.cloud.vault.database.backend}") String databaseBackend,
                   SecretLeaseContainer leaseContainer,
                   ContextRefresher contextRefresher) {

        final Log log = LogFactory.getLog(getClass());
        var vaultCredsPath = String.format("%s/creds/%s", databaseBackend, databaseRole);

        leaseContainer.addLeaseListener(event -> {
            if (vaultCredsPath.equals(event.getSource().getPath())) {
                if (event instanceof SecretLeaseCreatedEvent created) {
                    var username = created.getSecrets().get("username");
                    log.info("🔐 [VAULT LEASE CREATED] Initial dynamic credential issued: " + username
                            + " | Lease ID: " + created.getLease().getLeaseId()
                            + " | TTL: " + created.getLease().getLeaseDuration() + "s");
                } else if (event instanceof SecretLeaseRotatedEvent rotated) {
                    var username = rotated.getSecrets().get("username");
                    log.info("🔄 [VAULT LEASE ROTATED] New dynamic credential issued: " + username
                            + " | Lease ID: " + rotated.getLease().getLeaseId()
                            + " | TTL: " + rotated.getLease().getLeaseDuration() + "s");
                } else if (event instanceof SecretLeaseExpiredEvent expired) {
                    log.info("⚠️ [VAULT LEASE EXPIRED] Lease " + expired.getLease().getLeaseId()
                            + " reached max TTL and expired! Triggering @RefreshScope Context Refresh...");
                    contextRefresher.refresh();
                    log.info("✅ [CONTEXT REFRESHED] Database credentials refreshed for " + vaultCredsPath);
                }
            }
        });
    }
}
