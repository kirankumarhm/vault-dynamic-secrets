package com.hashicorp.vaultdynamicsecrets.controller;

import com.hashicorp.vaultdynamicsecrets.constants.ApiConstants;
import com.hashicorp.vaultdynamicsecrets.dto.PaymentRequest;
import com.hashicorp.vaultdynamicsecrets.dto.PaymentResponse;
import com.hashicorp.vaultdynamicsecrets.service.PaymentService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping(path = "/payments", produces = MediaType.APPLICATION_JSON_VALUE)
public class PaymentController {

    private final PaymentService service;

    public PaymentController(PaymentService service) {
        this.service = service;
    }

    @GetMapping
    public List<PaymentResponse> getPayments(
            @RequestParam(defaultValue = ApiConstants.DEFAULT_PAGE) int page,
            @RequestParam(defaultValue = ApiConstants.DEFAULT_SIZE) int size) {
        return service.list(page, size);
    }

    @GetMapping("/db-status")
    public Map<String, Object> getDbStatus() {
        return service.getDbStatus();
    }

    @GetMapping("/{id}")
    public PaymentResponse getPayment(@PathVariable String id) {
        return service.get(id);
    }

    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public PaymentResponse createPayment(@Valid @RequestBody PaymentRequest request) {
        return service.create(request.name(), request.ccInfo());
    }
}
