# ==============================================================================
# Namespace: vault
# ==============================================================================
resource "kubernetes_namespace" "vault" {
  metadata {
    name = var.vault_namespace
    labels = {
      "app.kubernetes.io/name"    = "vault"
      "app.kubernetes.io/instance" = "vault"
    }
  }
}

# ==============================================================================
# Automated mTLS Certificate Authority & Server Certificates
# ==============================================================================

# 1. Private Root CA
resource "tls_private_key" "ca_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca_cert" {
  private_key_pem = tls_private_key.ca_key.private_key_pem

  subject {
    common_name  = "Vault-Internal-Production-CA"
    organization = "HashiCorp Vault Production"
  }

  validity_period_hours = 8760 # 1 year
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
    "key_encipherment"
  ]
}

# 2. Vault Server TLS Certificate with SANs
resource "tls_private_key" "vault_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vault_csr" {
  private_key_pem = tls_private_key.vault_key.private_key_pem

  subject {
    common_name  = "vault.vault.svc.cluster.local"
    organization = "HashiCorp Vault Production"
  }

  dns_names = [
    "vault",
    "vault.vault",
    "vault.vault.svc",
    "vault.vault.svc.cluster.local",
    "*.vault-internal",
    "vault-0.vault-internal",
    "vault-1.vault-internal",
    "vault-2.vault-internal",
    "localhost"
  ]

  ip_addresses = [
    "127.0.0.1"
  ]
}

resource "tls_locally_signed_cert" "vault_cert" {
  cert_request_pem   = tls_cert_request.vault_csr.cert_request_pem
  ca_private_key_pem = tls_private_key.ca_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca_cert.cert_pem

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth"
  ]
}

# 3. Store CA & Server Certs as Kubernetes Secrets
resource "kubernetes_secret" "tls_ca" {
  metadata {
    name      = "tls-ca"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  data = {
    "ca.crt" = tls_self_signed_cert.ca_cert.cert_pem
  }

  type = "Opaque"
}

resource "kubernetes_secret" "tls_server" {
  metadata {
    name      = "tls-server"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  data = {
    "tls.crt" = tls_locally_signed_cert.vault_cert.cert_pem
    "tls.key" = tls_private_key.vault_key.private_key_pem
  }

  type = "kubernetes.io/tls"
}
