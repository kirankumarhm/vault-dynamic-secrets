package com.hashicorp.vaultdynamicsecrets;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.boot.test.context.SpringBootTest.WebEnvironment.RANDOM_PORT;

/**
 * Full-stack integration test: real HTTP -> controller -> service -> repository
 * -> Hibernate/JPA -> a real PostgreSQL in Testcontainers.
 *
 * Runs under maven-failsafe (`mvn verify`) and REQUIRES a Docker daemon. Vault is
 * disabled (see src/test/resources/application.properties); the datasource is
 * wired to the container via {@code @ServiceConnection}. Uses the JDK HTTP client
 * (no Spring test-client / Jackson deps) so it is robust across module changes.
 */
@Testcontainers
@SpringBootTest(webEnvironment = RANDOM_PORT)
class PaymentApiIT {

    @Container
    @ServiceConnection
    static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:17-alpine").withInitScript("db/schema.sql");

    @Value("${local.server.port}")
    int port;

    private final HttpClient http = HttpClient.newHttpClient();

    private HttpResponse<String> send(String method, String path, String body) throws Exception {
        var builder = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
                .header("Content-Type", "application/json")
                .header("Accept", "application/json");
        var publisher = (body == null)
                ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofString(body);
        return http.send(builder.method(method, publisher).build(), HttpResponse.BodyHandlers.ofString());
    }

    private static String extractId(String json) {
        Matcher m = Pattern.compile("\"id\"\\s*:\\s*\"([^\"]+)\"").matcher(json);
        assertThat(m.find()).as("response contains an id").isTrue();
        return m.group(1);
    }

    @Test
    void createThenFetchThenList() throws Exception {
        var created = send("POST", "/payments",
                "{\"name\":\"Ada Lovelace\",\"cc_info\":\"4111-1111-1111-1111\"}");
        assertThat(created.statusCode()).isEqualTo(201);
        assertThat(created.body()).contains("\"cc_info\":\"4111-1111-1111-1111\"");
        String id = extractId(created.body());

        var fetched = send("GET", "/payments/" + id, null);
        assertThat(fetched.statusCode()).isEqualTo(200);
        assertThat(fetched.body()).contains("Ada Lovelace");

        var list = send("GET", "/payments?size=50", null);
        assertThat(list.statusCode()).isEqualTo(200);
        assertThat(list.body()).startsWith("[").contains(id);
    }

    @Test
    void missingPayment_returns404ProblemJson() throws Exception {
        var resp = send("GET", "/payments/does-not-exist", null);
        assertThat(resp.statusCode()).isEqualTo(404);
        assertThat(resp.headers().firstValue("Content-Type").orElse(""))
                .contains("application/problem+json");
        assertThat(resp.body()).contains("Not found");
    }

    @Test
    void invalidCreate_returns400ProblemJson() throws Exception {
        var resp = send("POST", "/payments", "{\"name\":\"\",\"cc_info\":\"x\"}");
        assertThat(resp.statusCode()).isEqualTo(400);
        assertThat(resp.headers().firstValue("Content-Type").orElse(""))
                .contains("application/problem+json");
        assertThat(resp.body()).contains("Validation error");
    }

    @Test
    void securityHeadersPresentOnEveryResponse() throws Exception {
        var resp = send("GET", "/payments", null);
        assertThat(resp.headers().firstValue("X-Content-Type-Options")).hasValue("nosniff");
        assertThat(resp.headers().firstValue("X-Frame-Options")).hasValue("DENY");
        assertThat(resp.headers().firstValue("Content-Security-Policy")).hasValue("default-src 'self'");
        assertThat(resp.headers().firstValue("Cache-Control").orElse("")).contains("no-store");
    }

    @Test
    void paginationSizeIsCappedAndNeverErrors() throws Exception {
        var resp = send("GET", "/payments?size=100000", null);
        assertThat(resp.statusCode()).isEqualTo(200);
        assertThat(resp.body()).startsWith("[");
    }

    @Test
    void unmappedMethodIsRejected() throws Exception {
        // API exposes only GET/POST; DELETE on the item path is not mapped -> 405.
        var resp = send("DELETE", "/payments/whatever", null);
        assertThat(resp.statusCode()).isEqualTo(405);
    }
}
