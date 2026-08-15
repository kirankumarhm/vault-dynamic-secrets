package com.hashicorp.vaultdynamicsecrets.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.actuate.endpoint.annotation.Endpoint;
import org.springframework.boot.actuate.endpoint.annotation.ReadOperation;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Custom Spring Boot Actuator Endpoint for Vault Dynamic Secret Leases (/actuator/vault-lease).
 * Exposes real-time rotation telemetry, active lease details, and rotation counts.
 */
@Component
@Endpoint(id = "vaultLease")
public class VaultLeaseEndpoint {

    private final String databaseRole;
    private final String databaseBackend;
    private final String rotationStrategy;

    private volatile String currentUser = "UNKNOWN";
    private volatile Instant lastRotationTime = Instant.now();
    private final AtomicInteger rotationCount = new AtomicInteger(0);

    public VaultLeaseEndpoint(
            @Value("${spring.cloud.vault.database.role:payments-app}") String databaseRole,
            @Value("${spring.cloud.vault.database.backend:database}") String databaseBackend,
            @Value("${app.vault.rotation-strategy:refresh-scope}") String rotationStrategy) {
        this.databaseRole = databaseRole;
        this.databaseBackend = databaseBackend;
        this.rotationStrategy = rotationStrategy;
    }

    public void recordRotation(String username) {
        this.currentUser = username;
        this.lastRotationTime = Instant.now();
        this.rotationCount.incrementAndGet();
    }

    public void setCurrentUser(String username) {
        this.currentUser = username;
    }

    @ReadOperation
    public Map<String, Object> getVaultLeaseInfo() {
        Map<String, Object> info = new HashMap<>();
        info.put("status", "ACTIVE");
        info.put("role", databaseRole);
        info.put("backend", databaseBackend);
        info.put("rotationStrategy", rotationStrategy);
        info.put("activeDatabaseUser", currentUser);
        info.put("rotationCount", rotationCount.get());
        info.put("lastRotationTime", lastRotationTime.toString());
        return info;
    }
}
