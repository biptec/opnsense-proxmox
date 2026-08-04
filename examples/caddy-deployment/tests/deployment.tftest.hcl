mock_provider "opnsense" {}

run "application_owned_routes" {
  command = plan

  variables {
    routes = {
      "www.example.com" = {
        upstream_domains = ["10.20.0.10"]
        upstream_port    = 8080
        certificate_mode = "acme"
      }
      "service.internal.example.com" = {
        upstream_domains  = ["10.20.0.20"]
        upstream_port     = 8443
        upstream_protocol = "https"
        certificate_mode  = "internal"
        internal_ca_name  = "internal.example.com"
        allowed_networks  = ["10.0.0.0/8"]
        unbound_address   = "10.40.0.10"
      }
    }
  }

  assert {
    condition     = length(module.route) == 2
    error_message = "Each route entry must create one reverse-proxy module instance."
  }

  assert {
    condition = alltrue([
      for route in values(module.route) : route.preserve_host_header_id != ""
    ])
    error_message = "Every application route must preserve the frontend Host header by default."
  }

  assert {
    condition = (
      opnsense_unbound_host_override.route["service.internal.example.com"].hostname == "service" &&
      opnsense_unbound_host_override.route["service.internal.example.com"].domain == "internal.example.com" &&
      opnsense_unbound_host_override.route["service.internal.example.com"].server == "10.40.0.10"
    )
    error_message = "Internal split DNS must use the route FQDN and configured address."
  }

  assert {
    condition     = length(opnsense_unbound_host_override.route) == 1
    error_message = "Public routes must not create Unbound records implicitly."
  }
}

run "reject_empty_routes" {
  command = plan

  variables {
    routes = {}
  }

  expect_failures = [var.routes]
}

run "reject_invalid_domain" {
  command = plan

  variables {
    routes = {
      "invalid" = {
        upstream_domains = ["10.20.0.10"]
        upstream_port    = 80
      }
    }
  }

  expect_failures = [var.routes]
}

run "reject_invalid_upstream_port" {
  command = plan

  variables {
    routes = {
      "www.example.com" = {
        upstream_domains = ["10.20.0.10"]
        upstream_port    = 70000
      }
    }
  }

  expect_failures = [var.routes]
}

run "reject_internal_route_without_ca" {
  command = plan

  variables {
    routes = {
      "service.internal.example.com" = {
        upstream_domains = ["10.20.0.20"]
        upstream_port    = 80
        certificate_mode = "internal"
      }
    }
  }

  expect_failures = [var.routes]
}

run "reject_custom_route_without_certificate" {
  command = plan

  variables {
    routes = {
      "www.example.com" = {
        upstream_domains = ["10.20.0.10"]
        upstream_port    = 80
        certificate_mode = "custom"
      }
    }
  }

  expect_failures = [var.routes]
}
