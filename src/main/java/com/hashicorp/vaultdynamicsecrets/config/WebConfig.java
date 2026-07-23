package com.hashicorp.vaultdynamicsecrets.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Explicit CORS allow-list (checklist #44). Origins come from the
 * {@code app.cors.allowed-origins} property so they are configured per
 * environment — never a wildcard {@code *}.
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    private final String[] allowedOrigins;

    public WebConfig(@Value("${app.cors.allowed-origins}") String[] allowedOrigins) {
        this.allowedOrigins = allowedOrigins;
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/payments/**")
                .allowedOrigins(allowedOrigins)
                .allowedMethods("GET", "POST")
                .allowedHeaders("Content-Type")
                .maxAge(3600);
    }
}
