-- Test schema for the Testcontainers PostgreSQL integration test.
-- Mirrors scripts/schema.sql (the columns the JPA entity maps to). Kept minimal:
-- the app assigns the id (UUID) and created_at itself, so no pgcrypto/timezone setup.
CREATE TABLE IF NOT EXISTS payments
(
    id         VARCHAR(255) PRIMARY KEY NOT NULL,
    name       VARCHAR(255)             NOT NULL,
    cc_info    VARCHAR(255)             NOT NULL,
    created_at TIMESTAMP                NOT NULL
);
