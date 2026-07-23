package com.hashicorp.vaultdynamicsecrets.controller;

import com.hashicorp.vaultdynamicsecrets.dto.PaymentResponse;
import com.hashicorp.vaultdynamicsecrets.exception.PaymentNotFoundException;
import com.hashicorp.vaultdynamicsecrets.service.PaymentService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Web-layer slice test for {@link PaymentController}: routing, JSON contract,
 * bean-validation -> RFC 7807 400, not-found -> RFC 7807 404 (via
 * GlobalExceptionHandler), and the baseline security headers filter. The service
 * is mocked; no database or Vault is involved.
 */
@WebMvcTest(PaymentController.class)
class PaymentControllerTest {

    @Autowired
    MockMvc mvc;

    @MockitoBean
    PaymentService service;

    private static PaymentResponse sample(String id) {
        return new PaymentResponse(id, "Ada", "4111-1111-1111-1111", Instant.EPOCH);
    }

    @Test
    void getPayments_returnsJsonArray_withCcInfoKey() throws Exception {
        when(service.list(0, 20)).thenReturn(List.of(sample("id-1")));

        mvc.perform(get("/payments"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$[0].id").value("id-1"))
                .andExpect(jsonPath("$[0].cc_info").value("4111-1111-1111-1111"))
                // security headers filter applied to every response
                .andExpect(header().string("X-Content-Type-Options", "nosniff"))
                .andExpect(header().string("X-Frame-Options", "DENY"));
    }

    @Test
    void getPayment_returns200_whenFound() throws Exception {
        when(service.get("id-1")).thenReturn(sample("id-1"));

        mvc.perform(get("/payments/id-1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Ada"));
    }

    @Test
    void getPayment_returns404Problem_whenMissing() throws Exception {
        when(service.get("nope")).thenThrow(new PaymentNotFoundException("nope"));

        mvc.perform(get("/payments/nope").accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Not found"))
                .andExpect(jsonPath("$.status").value(404));
    }

    @Test
    void createPayment_returns201_whenValid() throws Exception {
        when(service.create(eq("Ada"), any())).thenReturn(sample("new-id"));

        mvc.perform(post("/payments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Ada\",\"cc_info\":\"4111-1111-1111-1111\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value("new-id"));
    }

    @Test
    void createPayment_returns400Problem_whenNameBlank() throws Exception {
        mvc.perform(post("/payments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"\",\"cc_info\":\"x\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Validation error"))
                .andExpect(jsonPath("$.errors.name").exists());
    }
}
