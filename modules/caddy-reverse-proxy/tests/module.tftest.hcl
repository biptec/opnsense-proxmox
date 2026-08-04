mock_provider "opnsense" {}

run "public_acme" {
  command = plan

  variables {
    domain           = "application.example.com"
    upstream_domains = ["10.20.0.10"]
    upstream_port    = 8080
  }

  assert {
    condition     = opnsense_caddy_domain.this.certificate_mode == "acme"
    error_message = "Public HTTPS must default to ACME."
  }

  assert {
    condition     = length(opnsense_caddy_header.preserve_host) == 1
    error_message = "Host preservation must be enabled by default."
  }

  assert {
    condition     = opnsense_caddy_handler.this.header_ids == toset([opnsense_caddy_header.preserve_host[0].id])
    error_message = "The generated Host header operation must be attached to the handler."
  }

  assert {
    condition     = opnsense_caddy_handler.this.upstream_protocol == "http"
    error_message = "The default upstream protocol must be HTTP."
  }
}

run "internal_with_access_list" {
  command = plan

  variables {
    domain                   = "application.internal.example"
    upstream_domains         = ["10.20.0.10", "10.20.0.11"]
    upstream_port            = 8443
    upstream_protocol        = "https"
    certificate_mode         = "internal"
    internal_ca_name         = "internal.example"
    allowed_networks         = ["10.0.0.0/24", "10.10.0.0/24"]
    load_balancing_policy    = "round_robin"
    upstream_tls_ca_ref_id   = "upstream-ca-ref"
    upstream_tls_server_name = "backend.internal.example"
  }

  assert {
    condition     = length(opnsense_caddy_access_list.this) == 1
    error_message = "allowed_networks must create one access list."
  }

  assert {
    condition     = opnsense_caddy_domain.this.access_list_id == opnsense_caddy_access_list.this[0].id
    error_message = "The generated access list must be attached to the Caddy domain."
  }

  assert {
    condition     = opnsense_caddy_domain.this.internal_certificate_lifetime_days == 3650
    error_message = "Internal certificates must default to ten years."
  }

  assert {
    condition     = opnsense_caddy_handler.this.tls_trust_ca_ref_id == "upstream-ca-ref"
    error_message = "The HTTPS upstream CA reference must reach the Caddy handler."
  }

  assert {
    condition     = opnsense_caddy_handler.this.tls_server_name == "backend.internal.example"
    error_message = "The HTTPS upstream server name must reach the Caddy handler."
  }
}


run "http_without_tls" {
  command = plan

  variables {
    domain            = "application.internal.example"
    upstream_domains  = ["10.20.0.10"]
    upstream_port     = 8080
    frontend_protocol = "http"
    certificate_mode  = "none"
  }

  assert {
    condition     = opnsense_caddy_domain.this.protocol == "http" && opnsense_caddy_domain.this.certificate_mode == "none"
    error_message = "A plain HTTP frontend must use certificate_mode none."
  }
}

run "custom_certificate" {
  command = plan

  variables {
    domain             = "application.example.com"
    upstream_domains   = ["10.20.0.10"]
    upstream_port      = 8080
    certificate_mode   = "custom"
    certificate_ref_id = "existing-certificate-ref"
  }

  assert {
    condition     = opnsense_caddy_domain.this.certificate_ref_id == "existing-certificate-ref"
    error_message = "A custom certificate reference must reach the Caddy domain."
  }
}

run "existing_access_list" {
  command = plan

  variables {
    domain           = "application.internal.example"
    upstream_domains = ["10.20.0.10"]
    upstream_port    = 8080
    access_list_id   = "existing-access-list"
  }

  assert {
    condition     = length(opnsense_caddy_access_list.this) == 0
    error_message = "An existing access_list_id must not create another access list."
  }

  assert {
    condition     = opnsense_caddy_domain.this.access_list_id == "existing-access-list"
    error_message = "The existing access list must be attached to the Caddy domain."
  }
}

run "reject_conflicting_access_lists" {
  command = plan

  variables {
    domain           = "application.internal.example"
    upstream_domains = ["10.20.0.10"]
    upstream_port    = 8080
    allowed_networks = ["10.0.0.0/24"]
    access_list_id   = "existing-access-list"
  }

  expect_failures = [opnsense_caddy_domain.this]
}

run "reject_internal_without_ca" {
  command = plan

  variables {
    domain           = "application.internal.example"
    upstream_domains = ["10.20.0.10"]
    upstream_port    = 8080
    certificate_mode = "internal"
  }

  expect_failures = [opnsense_caddy_domain.this]
}

run "reject_http_with_acme" {
  command = plan

  variables {
    domain            = "application.internal.example"
    upstream_domains  = ["10.20.0.10"]
    upstream_port     = 8080
    frontend_protocol = "http"
    certificate_mode  = "acme"
  }

  expect_failures = [opnsense_caddy_domain.this]
}

run "reject_custom_without_certificate" {
  command = plan

  variables {
    domain           = "application.example.com"
    upstream_domains = ["10.20.0.10"]
    upstream_port    = 8080
    certificate_mode = "custom"
  }

  expect_failures = [opnsense_caddy_domain.this]
}

run "reject_unknown_load_balancing_policy" {
  command = plan

  variables {
    domain                = "application.example.com"
    upstream_domains      = ["10.20.0.10"]
    upstream_port         = 8080
    load_balancing_policy = "unsupported"
  }

  expect_failures = [var.load_balancing_policy]
}

run "reject_upstream_tls_for_http" {
  command = plan

  variables {
    domain                 = "application.example.com"
    upstream_domains       = ["10.20.0.10"]
    upstream_port          = 8080
    upstream_protocol      = "http"
    upstream_tls_ca_ref_id = "upstream-ca-ref"
  }

  expect_failures = [opnsense_caddy_handler.this]
}

run "reject_health_uri_without_slash" {
  command = plan

  variables {
    domain           = "application.example.com"
    upstream_domains = ["10.20.0.10"]
    upstream_port    = 8080
    health_uri       = "healthz"
  }

  expect_failures = [var.health_uri]
}

run "reject_invalid_health_status" {
  command = plan

  variables {
    domain           = "application.example.com"
    upstream_domains = ["10.20.0.10"]
    upstream_port    = 8080
    health_status    = "700"
  }

  expect_failures = [var.health_status]
}


run "custom_headers_without_host_preservation" {
  command = plan

  variables {
    domain           = "application.example.com"
    upstream_domains = ["10.20.0.10"]
    upstream_port    = 8080
    preserve_host    = false
    header_ids       = ["custom-host-header", "security-header"]
  }

  assert {
    condition     = length(opnsense_caddy_header.preserve_host) == 0
    error_message = "preserve_host=false must not create a generated header operation."
  }

  assert {
    condition     = opnsense_caddy_handler.this.header_ids == toset(["custom-host-header", "security-header"])
    error_message = "Explicit header IDs must be attached unchanged."
  }
}
