package com.hashicorp.vaultdynamicsecrets.service;

import com.hashicorp.vaultdynamicsecrets.dto.PaymentResponse;
import com.hashicorp.vaultdynamicsecrets.entity.Payment;
import com.hashicorp.vaultdynamicsecrets.exception.PaymentNotFoundException;
import com.hashicorp.vaultdynamicsecrets.repository.PaymentRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for the business logic in {@link PaymentService}: pagination
 * clamping, not-found handling, and entity-to-DTO mapping. No Spring context.
 */
@ExtendWith(MockitoExtension.class)
class PaymentServiceTest {

    @Mock
    PaymentRepository repository;

    @InjectMocks
    PaymentService service;

    @Test
    void list_clampsOversizedPageToMax() {
        when(repository.findAll(any(Pageable.class))).thenReturn(new PageImpl<>(List.of()));

        service.list(0, 1000);

        var pageable = ArgumentCaptor.forClass(Pageable.class);
        verify(repository).findAll(pageable.capture());
        assertThat(pageable.getValue().getPageSize()).isEqualTo(100); // MAX_PAGE_SIZE
    }

    @Test
    void list_clampsSizeToMinAndNegativePageToZero() {
        when(repository.findAll(any(Pageable.class))).thenReturn(new PageImpl<>(List.of()));

        service.list(-5, 0);

        var pageable = ArgumentCaptor.forClass(Pageable.class);
        verify(repository).findAll(pageable.capture());
        assertThat(pageable.getValue().getPageSize()).isEqualTo(1); // MIN_PAGE_SIZE
        assertThat(pageable.getValue().getPageNumber()).isZero();
    }

    @Test
    void list_mapsEntityToResponse() {
        var entity = new Payment("id-1", "Ada", "cc-secret", Instant.EPOCH);
        when(repository.findAll(any(Pageable.class))).thenReturn(new PageImpl<>(List.of(entity)));

        List<PaymentResponse> result = service.list(0, 20);

        assertThat(result).singleElement().satisfies(r -> {
            assertThat(r.id()).isEqualTo("id-1");
            assertThat(r.name()).isEqualTo("Ada");
            assertThat(r.ccInfo()).isEqualTo("cc-secret");
            assertThat(r.createdAt()).isEqualTo(Instant.EPOCH);
        });
    }

    @Test
    void get_returnsMappedDto_whenFound() {
        when(repository.findById("id-1"))
                .thenReturn(Optional.of(new Payment("id-1", "Ada", "cc", Instant.EPOCH)));

        assertThat(service.get("id-1").name()).isEqualTo("Ada");
    }

    @Test
    void get_throwsNotFound_whenMissing() {
        when(repository.findById("missing")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.get("missing"))
                .isInstanceOf(PaymentNotFoundException.class)
                .hasMessageContaining("missing");
    }

    @Test
    void create_persistsEntityWithGeneratedIdAndTimestamp() {
        when(repository.save(any(Payment.class))).thenAnswer(inv -> inv.getArgument(0));

        PaymentResponse response = service.create("Grace", "4111-1111");

        var saved = ArgumentCaptor.forClass(Payment.class);
        verify(repository).save(saved.capture());
        assertThat(saved.getValue().getId()).isNotBlank();
        assertThat(saved.getValue().getName()).isEqualTo("Grace");
        assertThat(saved.getValue().getCcInfo()).isEqualTo("4111-1111");
        assertThat(saved.getValue().getCreatedAt()).isNotNull();
        // response reflects the persisted entity
        assertThat(response.id()).isEqualTo(saved.getValue().getId());
        assertThat(response.name()).isEqualTo("Grace");
    }
}
