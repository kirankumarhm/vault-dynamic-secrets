# ==============================================================================
# Database Provisioning: Amazon RDS (Real AWS) vs. In-Cluster Database (Floci)
# ==============================================================================

locals {
  postgres_host = var.use_floci ? "postgres.default.svc.cluster.local" : (
    length(aws_db_instance.postgres) > 0 ? aws_db_instance.postgres[0].address : var.postgres_host
  )
}

# ==============================================================================
# 1. REAL AWS PRODUCTION: Amazon RDS PostgreSQL (Multi-AZ with KMS Encryption)
# ==============================================================================
resource "aws_db_instance" "postgres" {
  count                  = var.use_floci ? 0 : 1
  identifier             = "payments-db-production"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = "db.t4g.medium"
  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_type           = "gp3"
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.vault_unseal.arn

  db_name                = var.postgres_db
  username               = var.postgres_admin_user
  password               = var.postgres_admin_password
  port                   = var.postgres_port

  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  backup_retention_period = 7
  auto_minor_version_upgrade = true

  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
    Application = "payments-service"
  }
}

# ==============================================================================
# 2. LOCAL FLOCI / KUBERNETES EMULATION: Automated In-Cluster PostgreSQL
# ==============================================================================

# ConfigMap with initial database schema mounted directly into docker-entrypoint-initdb.d
resource "kubernetes_config_map" "postgres_schema" {
  count = var.use_floci ? 1 : 0

  metadata {
    name      = "postgres-schema"
    namespace = "default"
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

# PostgreSQL Kubernetes Deployment
resource "kubernetes_deployment" "postgres" {
  count = var.use_floci ? 1 : 0

  metadata {
    name      = "postgres"
    namespace = "default"
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
            container_port = 5432
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

# PostgreSQL ClusterIP Service
resource "kubernetes_service" "postgres" {
  count = var.use_floci ? 1 : 0

  metadata {
    name      = "postgres"
    namespace = "default"
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
      port        = 5432
      target_port = 5432
    }
  }
}
