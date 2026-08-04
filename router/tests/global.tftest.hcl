mock_provider "opnsense" {}

run "global_router_policy" {
  command = plan

  variables {
    ingress_interface   = "lan"
    ingress_destination = "10.200.0.100"
  }

  assert {
    condition = (
      opnsense_caddy_settings.main.enabled &&
      opnsense_caddy_settings.main.http_port == 80 &&
      opnsense_caddy_settings.main.https_port == 443 &&
      opnsense_caddy_settings.main.run_as_user == "root"
    )
    error_message = "Global Caddy must bind directly to ports 80 and 443 as root."
  }

  assert {
    condition     = module.edge_ingress.destination == "10.200.0.100"
    error_message = "Global ingress must use the configured router destination."
  }
}

run "default_passthrough_interface" {
  command = plan

  variables {
    ingress_interface   = "wan"
    ingress_destination = null
  }

  assert {
    condition     = module.edge_ingress.destination == "wanip"
    error_message = "The default direct-interface deployment must match wanip."
  }
}

run "reject_invalid_ingress_interface" {
  command = plan

  variables {
    ingress_interface = "WAN public"
  }

  expect_failures = [var.ingress_interface]
}

run "reject_empty_acme_email" {
  command = plan

  variables {
    acme_email = ""
  }

  expect_failures = [var.acme_email]
}
