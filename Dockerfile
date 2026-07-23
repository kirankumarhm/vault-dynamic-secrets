# syntax=docker/dockerfile:1
#
# Production image for vault-dynamic-secrets.
#   - multi-stage: build with the full JDK+Maven, ship only a JRE
#   - Spring Boot layered extraction so dependency layers cache across rebuilds
#   - runs as a non-root user
#   - container-aware JVM sizing + fail-fast on OOM
#   - Docker HEALTHCHECK hits the actuator readiness probe
#
# Build (from this directory):  docker build -t vault-dynamic-secrets:latest .

########################################  Build  ########################################
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace

# Resolve dependencies first so the layer is cached unless pom.xml changes.
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -B -q dependency:go-offline

# Compile and package (unit/slice tests run in CI, not in the image build;
# the Testcontainers IT needs a Docker daemon and is excluded here).
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn -B -q -DskipTests clean package

# Split the fat jar into cacheable layers (Spring Boot "tools" jarmode).
RUN java -Djarmode=tools -jar target/vault-dynamic-secrets-*.jar \
        extract --layers --destination target/extracted

########################################  Runtime  ######################################
FROM eclipse-temurin:21-jre AS runtime

# curl only for the HEALTHCHECK below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Unprivileged runtime user.
RUN groupadd --system app && useradd --system --gid app --home-dir /app app
WORKDIR /app

# Copy layers least-volatile first for maximum cache reuse.
COPY --from=build --chown=app:app /workspace/target/extracted/dependencies/ ./
COPY --from=build --chown=app:app /workspace/target/extracted/spring-boot-loader/ ./
COPY --from=build --chown=app:app /workspace/target/extracted/snapshot-dependencies/ ./
COPY --from=build --chown=app:app /workspace/target/extracted/application/ ./

USER app
EXPOSE 8080

# Container-aware heap sizing (MaxRAMPercentage honours the container memory limit),
# plus the production flags mirrored from run.sh.
ENV JAVA_OPTS="-XX:+UseG1GC -XX:MaxRAMPercentage=75.0 -XX:MaxMetaspaceSize=256m \
-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp/heapdump.hprof -XX:+ExitOnOutOfMemoryError"

# Readiness probe (management.endpoint.health.probes.enabled=true exposes it).
HEALTHCHECK --interval=15s --timeout=3s --start-period=45s --retries=5 \
  CMD curl -fsS http://localhost:8080/actuator/health/readiness || exit 1

# JarLauncher runs the exploded layered app. sh -c so $JAVA_OPTS is expanded.
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]
