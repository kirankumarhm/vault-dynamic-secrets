package com.hashicorp.vaultdynamicsecrets.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

/**
 * A stored payment record. Persistence-only — never serialized to clients
 * directly (the controller returns a {@code PaymentResponse} DTO instead).
 *
 * The id is a caller-assigned UUID string, so there is no {@code @GeneratedValue}.
 */
@Entity
@Table(name = "payments")
public class Payment {

    @Id
    private String id;

    private String name;

    @Column(name = "cc_info")
    private String ccInfo;

    @Column(name = "created_at")
    private Instant createdAt;

    /** Required by JPA. */
    protected Payment() {
    }

    public Payment(String id, String name, String ccInfo, Instant createdAt) {
        this.id = id;
        this.name = name;
        this.ccInfo = ccInfo;
        this.createdAt = createdAt;
    }

    public String getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public String getCcInfo() {
        return ccInfo;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
