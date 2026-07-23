package com.hashicorp.vaultdynamicsecrets.repository;

import com.hashicorp.vaultdynamicsecrets.entity.Payment;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Data access for payments via Spring Data JPA.
 *
 * The application {@link javax.sql.DataSource} is the {@code @RefreshScope}
 * bean, so when Vault rotates the dynamic DB credentials the underlying
 * connection pool is swapped transparently — Hibernate obtains connections
 * through the same proxy and needs no rotation logic here.
 *
 * CRUD, {@code findById}, and {@code findAll(Pageable)} come from
 * {@link JpaRepository}; no SQL is hand-written (Spring Data parameterizes all
 * queries, so there is no injection surface).
 *
 * Spring Data auto-registers this interface as a bean — no {@code @Repository}
 * stereotype is needed.
 */
public interface PaymentRepository extends JpaRepository<Payment, String> {
}
