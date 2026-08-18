output "postgres_host" {
  description = "Active PostgreSQL database host (RDS address or internal Kubernetes Service)"
  value       = local.postgres_host
}

output "postgres_port" {
  description = "Active PostgreSQL database port"
  value       = var.postgres_port
}

output "postgres_db" {
  description = "Database name"
  value       = var.postgres_db
}

output "postgres_admin_user" {
  description = "Database master administrator user"
  value       = var.postgres_admin_user
}

output "postgres_admin_password" {
  description = "Database master administrator password"
  value       = var.postgres_admin_password
  sensitive   = true
}
