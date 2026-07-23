package com.hashicorp.vaultdynamicsecrets.config;

import org.apache.commons.logging.LogFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.jdbc.DataSourceBuilder;
import org.springframework.boot.jdbc.autoconfigure.DataSourceProperties;
import org.springframework.cloud.context.config.annotation.RefreshScope;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.sql.DataSource;

/**
 * Builds the application {@link DataSource} from the properties Vault supplies.
 *
 * The bean is {@code @RefreshScope} so that when Vault rotates the dynamic DB
 * credentials (and the context is refreshed) the pool is rebuilt with the new
 * username/password — the rest of the app is unaware.
 *
 * Active only for the {@code refresh-scope} rotation strategy (the default).
 * With {@code app.vault.rotation-strategy=mxbean} this bean backs off, Boot
 * auto-configures a plain HikariCP {@link DataSource}, and
 * {@link HikariCredentialRotator} hot-swaps credentials on the live pool
 * instead — see {@code application.properties}.
 */
@Configuration
public class DataSourceConfig {

    @Bean
    @RefreshScope
    @ConditionalOnProperty(name = "app.vault.rotation-strategy",
            havingValue = "refresh-scope", matchIfMissing = true)
    DataSource dataSource(DataSourceProperties properties) {
        var log = LogFactory.getLog(getClass());
        var db = DataSourceBuilder
                .create()
                .url(properties.getUrl())
                .username(properties.getUsername())
                .password(properties.getPassword())
                .build();
        // Log the Vault-issued username only — NEVER the password (secrets must not reach logs).
        log.info("Rebuilt datasource with Vault-issued user " + properties.getUsername());
        return db;
    }
}
