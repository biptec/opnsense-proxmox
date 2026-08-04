mock_provider "opnsense" {}

run "default_wan_ingress" {
  command = plan

  assert {
    condition = (
      contains(opnsense_firewall_nat_port_forward.http.interface, "wan") &&
      opnsense_firewall_nat_port_forward.http.destination.net == "wanip" &&
      opnsense_firewall_nat_port_forward.http.destination.port == "80" &&
      opnsense_firewall_nat_port_forward.http.target.ip == "127.0.0.1" &&
      opnsense_firewall_nat_port_forward.http.target.port == "8080"
    )
    error_message = "Default HTTP ingress must translate wanip:80 to loopback:8080."
  }

  assert {
    condition = (
      contains(opnsense_firewall_nat_port_forward.https.interface, "wan") &&
      opnsense_firewall_nat_port_forward.https.destination.net == "wanip" &&
      opnsense_firewall_nat_port_forward.https.destination.port == "443" &&
      opnsense_firewall_nat_port_forward.https.target.ip == "127.0.0.1" &&
      opnsense_firewall_nat_port_forward.https.target.port == "8443"
    )
    error_message = "Default HTTPS ingress must translate wanip:443 to loopback:8443."
  }

  assert {
    condition = (
      opnsense_firewall_filter.http.filter.destination.net == "127.0.0.1" &&
      opnsense_firewall_filter.http.filter.destination.port == "8080" &&
      opnsense_firewall_filter.https.filter.destination.net == "127.0.0.1" &&
      opnsense_firewall_filter.https.filter.destination.port == "8443"
    )
    error_message = "Filter rules must match the post-NAT loopback destinations."
  }

  assert {
    condition = (
      opnsense_firewall_nat_port_forward.http.nat_reflection == "disable" &&
      opnsense_firewall_nat_port_forward.https.nat_reflection == "disable"
    )
    error_message = "NAT reflection must be disabled by default."
  }
}

run "custom_interface_and_ports" {
  command = plan

  variables {
    interface           = "opt2"
    destination         = "203.0.113.10"
    source_network      = "198.51.100.0/24"
    external_http_port  = 8081
    external_https_port = 8444
    caddy_http_port     = 18080
    caddy_https_port    = 18443
    sequence_base       = 300
    nat_reflection      = "enable"
    log_nat             = true
    log_filter          = true
    no_xmlrpc_sync      = true
    description_prefix  = "Public Caddy"
  }

  assert {
    condition = (
      contains(opnsense_firewall_nat_port_forward.http.interface, "opt2") &&
      opnsense_firewall_nat_port_forward.http.destination.net == "203.0.113.10" &&
      opnsense_firewall_nat_port_forward.http.source.net == "198.51.100.0/24" &&
      opnsense_firewall_nat_port_forward.http.destination.port == "8081" &&
      opnsense_firewall_nat_port_forward.http.target.port == "18080" &&
      opnsense_firewall_nat_port_forward.http.sequence == 300 &&
      opnsense_firewall_nat_port_forward.https.sequence == 301
    )
    error_message = "Custom interface, addresses, ports, and sequence must reach the NAT rules."
  }

  assert {
    condition = (
      opnsense_firewall_nat_port_forward.http.log &&
      opnsense_firewall_filter.http.filter.log &&
      opnsense_firewall_filter.http.no_xmlrpc_sync &&
      opnsense_firewall_nat_port_forward.http.nat_reflection == "enable"
    )
    error_message = "Logging, HA sync, and NAT reflection settings must reach generated rules."
  }
}

run "disabled_rules" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition = (
      !opnsense_firewall_nat_port_forward.http.enabled &&
      !opnsense_firewall_nat_port_forward.https.enabled &&
      !opnsense_firewall_filter.http.enabled &&
      !opnsense_firewall_filter.https.enabled
    )
    error_message = "enabled=false must disable every generated rule."
  }
}

run "reject_empty_interface" {
  command = plan

  variables {
    interface = ""
  }

  expect_failures = [var.interface]
}

run "reject_invalid_interface_identifier" {
  command = plan

  variables {
    interface = "WAN public"
  }

  expect_failures = [var.interface]
}

run "reject_empty_destination" {
  command = plan

  variables {
    destination = ""
  }

  expect_failures = [var.destination]
}

run "reject_duplicate_external_ports" {
  command = plan

  variables {
    external_http_port  = 443
    external_https_port = 443
  }

  expect_failures = [opnsense_firewall_nat_port_forward.http]
}

run "reject_duplicate_caddy_ports" {
  command = plan

  variables {
    caddy_http_port  = 8080
    caddy_https_port = 8080
  }

  expect_failures = [opnsense_firewall_nat_port_forward.http]
}

run "reject_external_internal_port_overlap" {
  command = plan

  variables {
    external_http_port = 8080
    caddy_http_port    = 8080
  }

  expect_failures = [opnsense_firewall_nat_port_forward.http]
}

run "reject_webui_caddy_port" {
  command = plan

  variables {
    caddy_http_port = 80
  }

  expect_failures = [opnsense_firewall_nat_port_forward.http]
}

run "reject_invalid_nat_reflection" {
  command = plan

  variables {
    nat_reflection = "automatic"
  }

  expect_failures = [var.nat_reflection]
}

run "reject_invalid_description" {
  command = plan

  variables {
    description_prefix = "Caddy ingress: public"
  }

  expect_failures = [var.description_prefix]
}

run "reject_invalid_port" {
  command = plan

  variables {
    external_http_port = 70000
  }

  expect_failures = [var.external_http_port]
}

run "reject_invalid_sequence" {
  command = plan

  variables {
    sequence_base = 0
  }

  expect_failures = [var.sequence_base]
}
