package com.hashicorp.vaultdynamicsecrets.service;

import com.hashicorp.vaultdynamicsecrets.constants.ApiConstants;
import com.hashicorp.vaultdynamicsecrets.dto.PaymentResponse;
import com.hashicorp.vaultdynamicsecrets.entity.Payment;
import com.hashicorp.vaultdynamicsecrets.exception.PaymentNotFoundException;
import com.hashicorp.vaultdynamicsecrets.repository.PaymentRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Business logic for payments. Sits between the controller and the repository:
 * the controller stays transport-only, the repository stays persistence-only,
 * and pagination bounds / not-found handling / entity-to-DTO mapping live here.
 */
@Service
@Transactional(readOnly = true)
public class PaymentService {

    private final PaymentRepository repository;

    public PaymentService(PaymentRepository repository) {
        this.repository = repository;
    }

    /**
     * List payments with bounded pagination — never returns an unbounded result set.
     * {@code size} is clamped to [{@value ApiConstants#MIN_PAGE_SIZE}, {@value ApiConstants#MAX_PAGE_SIZE}]
     * and {@code page} to >= 0.
     */
    public List<PaymentResponse> list(int page, int size) {
        int safeSize = Math.min(Math.max(size, ApiConstants.MIN_PAGE_SIZE), ApiConstants.MAX_PAGE_SIZE);
        int safePage = Math.max(page, 0);
        return repository.findAll(PageRequest.of(safePage, safeSize, Sort.by("createdAt")))
                .map(PaymentService::toResponse)
                .getContent();
    }

    public PaymentResponse get(String id) {
        return repository.findById(id)
                .map(PaymentService::toResponse)
                .orElseThrow(() -> new PaymentNotFoundException(id));
    }

    @Transactional
    public PaymentResponse create(String name, String ccInfo) {
        var saved = repository.save(
                new Payment(UUID.randomUUID().toString(), name, ccInfo, Instant.now()));
        return toResponse(saved);
    }

    private static PaymentResponse toResponse(Payment p) {
        return new PaymentResponse(p.getId(), p.getName(), p.getCcInfo(), p.getCreatedAt());
    }
}
