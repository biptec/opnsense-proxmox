mock_provider "opnsense" {}

variables {
  import_caddy_settings = false
  public_destination    = "198.51.100.80"
}

run "dual_ingress_composition" {
  command = plan

  variables {
    management_interface       = "lan"
    public_ingress_interface   = "wan"
    internal_ingress_interface = "opt2"
    internal_service_address   = "10.40.0.10"
    internal_source_network    = "TRUSTED_INTERNALS"
    public_domain              = "application.example.com"
    public_upstream_domains    = ["10.20.0.10"]
    public_upstream_port       = 8080
    internal_domain            = "application.internal.example.com"
    internal_upstream_domains  = ["10.20.0.20"]
    internal_upstream_port     = 8443
    internal_ca_name           = "internal.example.com"
  }

  assert {
    condition = (
      opnsense_caddy_settings.main.enabled &&
      opnsense_caddy_settings.main.http_port == 8080 &&
      opnsense_caddy_settings.main.https_port == 8443 &&
      opnsense_caddy_settings.main.listen_addresses == toset(["198.51.100.80", "10.40.0.10"])
    )
    error_message = "Caddy settings must enable only the dedicated public and internal listeners."
  }

  assert {
    condition     = module.public_ingress.destination == "198.51.100.80"
    error_message = "Public ingress must target the dedicated public Caddy address."
  }

  assert {
    condition     = module.internal_ingress.destination == "10.40.0.10"
    error_message = "Internal ingress must match the dedicated service address."
  }

  assert {
    condition     = opnsense_unbound_host_override.internal_proxy.hostname == "application" && opnsense_unbound_host_override.internal_proxy.domain == "internal.example.com"
    error_message = "The internal FQDN must be split into the correct Unbound hostname and zone."
  }

  assert {
    condition     = opnsense_unbound_host_override.internal_proxy.server == "10.40.0.10"
    error_message = "Unbound must resolve the internal FQDN to the internal service address."
  }
}

run "reject_management_public_overlap" {
  command = plan

  variables {
    management_interface       = "wan"
    public_ingress_interface   = "wan"
    internal_ingress_interface = "opt2"
    internal_service_address   = "10.40.0.10"
    public_domain              = "application.example.com"
    public_upstream_domains    = ["10.20.0.10"]
    public_upstream_port       = 8080
    internal_domain            = "application.internal.example.com"
    internal_upstream_domains  = ["10.20.0.20"]
    internal_upstream_port     = 8443
    internal_ca_name           = "internal.example.com"
  }

  expect_failures = [opnsense_caddy_settings.main]
}

run "reject_management_internal_overlap" {
  command = plan

  variables {
    management_interface       = "lan"
    public_ingress_interface   = "wan"
    internal_ingress_interface = "lan"
    internal_service_address   = "10.40.0.10"
    public_domain              = "application.example.com"
    public_upstream_domains    = ["10.20.0.10"]
    public_upstream_port       = 8080
    internal_domain            = "application.internal.example.com"
    internal_upstream_domains  = ["10.20.0.20"]
    internal_upstream_port     = 8443
    internal_ca_name           = "internal.example.com"
  }

  expect_failures = [opnsense_caddy_settings.main]
}

run "reject_shared_ingress_interface" {
  command = plan

  variables {
    management_interface       = "lan"
    public_ingress_interface   = "wan"
    internal_ingress_interface = "wan"
    internal_service_address   = "10.40.0.10"
    public_domain              = "application.example.com"
    public_upstream_domains    = ["10.20.0.10"]
    public_upstream_port       = 8080
    internal_domain            = "application.internal.example.com"
    internal_upstream_domains  = ["10.20.0.20"]
    internal_upstream_port     = 8443
    internal_ca_name           = "internal.example.com"
  }

  expect_failures = [opnsense_caddy_settings.main]
}

run "reject_duplicate_domains" {
  command = plan

  variables {
    management_interface       = "lan"
    public_ingress_interface   = "wan"
    internal_ingress_interface = "opt2"
    internal_service_address   = "10.40.0.10"
    public_domain              = "application.example.com"
    public_upstream_domains    = ["10.20.0.10"]
    public_upstream_port       = 8080
    internal_domain            = "application.example.com"
    internal_upstream_domains  = ["10.20.0.20"]
    internal_upstream_port     = 8443
    internal_ca_name           = "internal.example.com"
  }

  expect_failures = [opnsense_caddy_settings.main]
}

run "reject_internal_address_with_prefix" {
  command = plan

  variables {
    management_interface       = "lan"
    public_ingress_interface   = "wan"
    internal_ingress_interface = "opt2"
    internal_service_address   = "10.40.0.10/24"
    public_domain              = "application.example.com"
    public_upstream_domains    = ["10.20.0.10"]
    public_upstream_port       = 8080
    internal_domain            = "application.internal.example.com"
    internal_upstream_domains  = ["10.20.0.20"]
    internal_upstream_port     = 8443
    internal_ca_name           = "internal.example.com"
  }

  expect_failures = [var.internal_service_address]
}

run "reject_single_label_internal_domain" {
  command = plan

  variables {
    management_interface       = "lan"
    public_ingress_interface   = "wan"
    internal_ingress_interface = "opt2"
    internal_service_address   = "10.40.0.10"
    public_domain              = "application.example.com"
    public_upstream_domains    = ["10.20.0.10"]
    public_upstream_port       = 8080
    internal_domain            = "application"
    internal_upstream_domains  = ["10.20.0.20"]
    internal_upstream_port     = 8443
    internal_ca_name           = "internal.example.com"
  }

  expect_failures = [var.internal_domain]
}

run "reject_invalid_dns_label" {
  command = plan

  variables {
    management_interface       = "lan"
    public_ingress_interface   = "wan"
    internal_ingress_interface = "opt2"
    internal_service_address   = "10.40.0.10"
    public_domain              = "application-.example.com"
    public_upstream_domains    = ["10.20.0.10"]
    public_upstream_port       = 8080
    internal_domain            = "application.internal.example.com"
    internal_upstream_domains  = ["10.20.0.20"]
    internal_upstream_port     = 8443
    internal_ca_name           = "internal.example.com"
  }

  expect_failures = [var.public_domain]
}

run "reject_duplicate_listener_address" {
  command = plan

  variables {
    public_destination         = "10.40.0.10"
    management_interface       = "lan"
    public_ingress_interface   = "wan"
    internal_ingress_interface = "opt2"
    internal_service_address   = "10.40.0.10"
    public_domain              = "application.example.com"
    public_upstream_domains    = ["10.20.0.10"]
    public_upstream_port       = 8080
    internal_domain            = "application.internal.example.com"
    internal_upstream_domains  = ["10.20.0.20"]
    internal_upstream_port     = 8443
    internal_ca_name           = "internal.example.com"
  }

  expect_failures = [opnsense_caddy_settings.main]
}
