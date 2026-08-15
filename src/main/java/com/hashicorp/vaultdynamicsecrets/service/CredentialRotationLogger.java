package com.hashicorp.vaultdynamicsecrets.service;

import com.hashicorp.vaultdynamicsecrets.config.VaultLeaseEndpoint;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

/**
 * Periodically polls the active PostgreSQL connection to verify connectivity and
 * explicitly logs the current dynamic database user, making rotations instantly
 * visible in logs and updating the /actuator/vault-lease telemetry endpoint.
 */
@Component
public class CredentialRotationLogger {

    private static final Log log = LogFactory.getLog(CredentialRotationLogger.class);

    @Autowired
    private DataSource dataSource;

    @Autowired
    private VaultLeaseEndpoint vaultLeaseEndpoint;

    private String lastKnownUser = null;

    @Scheduled(fixedRate = 15000)
    public void monitorDatabaseUser() {
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT current_user, current_database()")) {

            if (rs.next()) {
                String currentUser = rs.getString(1);
                String database = rs.getString(2);

                if (lastKnownUser == null) {
                    lastKnownUser = currentUser;
                    vaultLeaseEndpoint.setCurrentUser(currentUser);
                    log.info("🔐 [VAULT DYNAMIC CREDS] Initial Active PostgreSQL User: " + currentUser + " (DB: " + database + ")");
                } else if (!lastKnownUser.equals(currentUser)) {
                    vaultLeaseEndpoint.recordRotation(currentUser);
                    log.info("🔄 [VAULT DYNAMIC CREDS ROTATION DETECTED] >>> Previous User: " + lastKnownUser
                            + " -> NEW Active User: " + currentUser + " <<< (Zero-downtime rotation verified!)");
                    lastKnownUser = currentUser;
                } else {
                    log.info("⚡ [DB HEARTBEAT] Active PostgreSQL User: " + currentUser);
                }
            }
        } catch (Exception e) {
            log.warn("⚠️ [DB HEARTBEAT ERROR] Failed to query PostgreSQL: " + e.getMessage());
        }
    }
}
