package com.hashicorp.vaultdynamicsecrets.config;

import io.micrometer.tracing.Tracer;
import io.micrometer.tracing.handler.DefaultTracingObservationHandler;
import io.micrometer.tracing.otel.bridge.OtelCurrentTraceContext;
import io.micrometer.tracing.otel.bridge.OtelTracer;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/**
 * Manual OTLP tracing wiring — Spring Boot 4.0 removed tracing auto-configuration.
 */
@Configuration
public class TracingConfig {

    @Bean
    OtlpHttpSpanExporter otlpHttpSpanExporter(
            @Value("${management.otlp.tracing.endpoint}") String endpoint) {
        return OtlpHttpSpanExporter.builder()
                .setEndpoint(endpoint)
                .setTimeout(Duration.ofSeconds(5))
                .build();
    }

    @Bean
    SdkTracerProvider sdkTracerProvider(
            OtlpHttpSpanExporter exporter,
            @Value("${spring.application.name}") String appName) {
        Resource resource = Resource.getDefault().toBuilder()
                .put(AttributeKey.stringKey("service.name"), appName)
                .build();
        return SdkTracerProvider.builder()
                .setResource(resource)
                .addSpanProcessor(BatchSpanProcessor.builder(exporter).build())
                .build();
    }

    @Bean
    OpenTelemetry openTelemetry(SdkTracerProvider sdkTracerProvider) {
        return OpenTelemetrySdk.builder()
                .setTracerProvider(sdkTracerProvider)
                .buildAndRegisterGlobal();
    }

    @Bean
    OtelCurrentTraceContext otelCurrentTraceContext() {
        return new OtelCurrentTraceContext();
    }

    @Bean
    Tracer tracer(OpenTelemetry openTelemetry, OtelCurrentTraceContext otelCurrentTraceContext) {
        io.opentelemetry.api.trace.Tracer otelTracer =
                openTelemetry.getTracer("vault-dynamic-secrets");
        return new OtelTracer(otelTracer, otelCurrentTraceContext, event -> {});
    }

    // Registers the tracer as an ObservationHandler so Spring MVC observations produce spans.
    @Bean
    DefaultTracingObservationHandler defaultTracingObservationHandler(Tracer tracer) {
        return new DefaultTracingObservationHandler(tracer);
    }
}
