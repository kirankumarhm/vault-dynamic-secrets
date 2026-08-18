# ==============================================================================
# Module: modules/database
# Purpose: Provisions Amazon RDS PostgreSQL (for AWS Production) or automated
#          in-cluster PostgreSQL with schema initialization (for Floci/Local).
# ==============================================================================

locals {
  postgres_host = var.use_floci ? "postgres.${var.app_namespace}.svc.cluster.local" : (
    length(aws_db_instance.postgres) > 0 ? aws_db_instance.postgres[0].address : "localhost"
  )
}

# 1. Real AWS Production: Amazon RDS PostgreSQL (Multi-AZ with KMS Encryption)
resource "aws_db_instance" "postgres" {
  count                  = var.use_floci ? 0 : 1
  identifier             = "payments-db-${var.environment}"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = "db.t4g.medium"
  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_type           = "gp3"
  storage_encrypted      = true
  kms_key_id             = var.kms_key_arn

  db_name                = var.postgres_db
  username               = var.postgres_admin_user
  password               = var.postgres_admin_password
  port                   = var.postgres_port

  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  backup_retention_period    = 7
  auto_minor_version_upgrade = true

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Application = "payments-service"
  }
}

# 2. Local Floci / Kubernetes Emulation: In-Cluster PostgreSQL with Schema ConfigMap
resource "kubernetes_config_map" "postgres_schema" {
  count = var.use_floci ? 1 : 0

  metadata {
    name      = "postgres-schema"
    namespace = var.app_namespace
  }

  data = {
    "init.sql" = <<-EOT
      SET TIME ZONE 'UTC';
      CREATE EXTENSION IF NOT EXISTS pgcrypto;

      CREATE TABLE IF NOT EXISTS payments (
        id VARCHAR(255) PRIMARY KEY NOT NULL,
        name VARCHAR(255) NOT NULL,
        cc_info VARCHAR(255) NOT NULL,
        created_at TIMESTAMP NOT NULL
      );
    EOT
  }
}

resource "kubernetes_deployment" "postgres" {
  count = var.use_floci ? 1 : 0

  metadata {
    name      = "postgres"
    namespace = var.app_namespace
    labels = {
      app = "postgres"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name              = "postgres"
          image             = "postgres:18.4"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = var.postgres_port
          }

          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }
          env {
            name  = "POSTGRES_USER"
            value = var.postgres_admin_user
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = var.postgres_admin_password
          }

          volume_mount {
            name       = "init-schema"
            mount_path = "/docker-entrypoint-initdb.d"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "init-schema"
          config_map {
            name = kubernetes_config_map.postgres_schema[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  count = var.use_floci ? 1 : 0

  metadata {
    name      = "postgres"
    namespace = var.app_namespace
    labels = {
      app = "postgres"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "postgres"
    }

    port {
      name        = "postgres"
      port        = var.postgres_port
      target_port = var.postgres_port
    }
  }
}
