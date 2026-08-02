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
    condition     = opnsense_caddy_handler.this.upstream_protocol == "http"
    error_message = "The default upstream protocol must be HTTP."
  }
}

run "internal_with_access_list" {
  command = plan

  variables {
    domain                = "application.internal.example"
    upstream_domains      = ["10.20.0.10", "10.20.0.11"]
    upstream_port         = 8443
    upstream_protocol     = "https"
    certificate_mode      = "internal"
    internal_ca_name      = "internal.example"
    allowed_networks      = ["10.0.0.0/24", "10.10.0.0/24"]
    load_balancing_policy = "round_robin"
  }

  assert {
    condition     = length(opnsense_caddy_access_list.this) == 1
    error_message = "allowed_networks must create one access list."
  }

  assert {
    condition     = opnsense_caddy_domain.this.internal_certificate_lifetime_days == 3650
    error_message = "Internal certificates must default to ten years."
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
