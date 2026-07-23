package com.hashicorp.vaultdynamicsecrets.exception;

/**
 * Thrown by the service layer when a requested payment does not exist.
 * Mapped to a 404 {@code application/problem+json} response by
 * {@link GlobalExceptionHandler}.
 */
public class PaymentNotFoundException extends RuntimeException {

    public PaymentNotFoundException(String id) {
        super("No payment with id " + id);
    }
}
