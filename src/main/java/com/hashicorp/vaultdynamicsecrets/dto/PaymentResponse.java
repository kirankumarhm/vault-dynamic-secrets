package com.hashicorp.vaultdynamicsecrets.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;

/**
 * Outgoing payment representation (API response). Decouples the JSON contract
 * from the {@code Payment} JPA entity so persistence changes never leak to
 * clients.
 */
public record PaymentResponse(
        String id,
        String name,
        @JsonProperty("cc_info") String ccInfo,
        Instant createdAt) {
}
