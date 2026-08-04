mock_provider "opnsense" {}

run "default_wan_ingress" {
  command = plan

  assert {
    condition = (
      contains(opnsense_firewall_filter.http.interface.interface, "wan") &&
      opnsense_firewall_filter.http.filter.destination.net == "wanip" &&
      opnsense_firewall_filter.http.filter.destination.port == "80" &&
      opnsense_firewall_filter.https.filter.destination.net == "wanip" &&
      opnsense_firewall_filter.https.filter.destination.port == "443"
    )
    error_message = "Default ingress must permit wanip ports 80 and 443 directly."
  }

  assert {
    condition = (
      opnsense_firewall_filter.http.filter.source.net == "any" &&
      opnsense_firewall_filter.http.sequence == 100 &&
      opnsense_firewall_filter.https.sequence == 101
    )
    error_message = "Default source and rule sequence are incorrect."
  }
}

run "custom_interface_and_ports" {
  command = plan

  variables {
    interface          = "opt2"
    destination        = "203.0.113.10"
    source_network     = "198.51.100.0/24"
    http_port          = 8081
    https_port         = 8444
    sequence_base      = 300
    log                = true
    no_xmlrpc_sync     = true
    description_prefix = "Public Caddy"
  }

  assert {
    condition = (
      contains(opnsense_firewall_filter.http.interface.interface, "opt2") &&
      opnsense_firewall_filter.http.filter.destination.net == "203.0.113.10" &&
      opnsense_firewall_filter.http.filter.source.net == "198.51.100.0/24" &&
      opnsense_firewall_filter.http.filter.destination.port == "8081" &&
      opnsense_firewall_filter.https.filter.destination.port == "8444" &&
      opnsense_firewall_filter.http.sequence == 300 &&
      opnsense_firewall_filter.https.sequence == 301
    )
    error_message = "Custom ingress values must reach both filter rules."
  }

  assert {
    condition = (
      opnsense_firewall_filter.http.filter.log &&
      opnsense_firewall_filter.http.no_xmlrpc_sync
    )
    error_message = "Logging and HA sync settings must reach generated rules."
  }
}

run "disabled_rules" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition = (
      !opnsense_firewall_filter.http.enabled &&
      !opnsense_firewall_filter.https.enabled
    )
    error_message = "enabled=false must disable both generated rules."
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

run "reject_invalid_http_port" {
  command = plan

  variables {
    http_port = 70000
  }

  expect_failures = [var.http_port]
}

run "reject_invalid_https_port" {
  command = plan

  variables {
    https_port = 0
  }

  expect_failures = [var.https_port]
}

run "reject_invalid_description" {
  command = plan

  variables {
    description_prefix = "Caddy ingress: public"
  }

  expect_failures = [var.description_prefix]
}

run "reject_invalid_sequence" {
  command = plan

  variables {
    sequence_base = 0
  }

  expect_failures = [var.sequence_base]
}
