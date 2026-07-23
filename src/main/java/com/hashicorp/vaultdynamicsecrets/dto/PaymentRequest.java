package com.hashicorp.vaultdynamicsecrets.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Incoming payment creation request. Validated with Bean Validation so bad
 * input is rejected with an RFC 7807 problem response before touching the DB.
 */
public record PaymentRequest(
        @NotBlank(message = "name is required")
        @Size(max = 255, message = "name must be at most 255 characters")
        String name,

        @NotBlank(message = "cc_info is required")
        @Size(max = 255, message = "cc_info must be at most 255 characters")
        @JsonProperty("cc_info") String ccInfo) {
}
