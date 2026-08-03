locals {
  destination_net         = var.destination != null ? var.destination : "${var.interface}ip"
  ports_are_distinct      = length(toset([var.external_http_port, var.external_https_port, var.caddy_http_port, var.caddy_https_port])) == 4
  caddy_ports_avoid_webui = !contains([80, 443], var.caddy_http_port) && !contains([80, 443], var.caddy_https_port)
  http_sequence           = var.sequence_base
  https_sequence          = var.sequence_base + 1
}

resource "opnsense_firewall_nat_port_forward" "http" {
  enabled     = var.enabled
  sequence    = local.http_sequence
  interface   = [var.interface]
  ip_protocol = "inet"
  protocol    = "tcp"
  log         = var.log_nat

  source = {
    net = var.source_network
  }

  destination = {
    net  = local.destination_net
    port = tostring(var.external_http_port)
  }

  target = {
    ip   = "127.0.0.1"
    port = tostring(var.caddy_http_port)
  }

  nat_reflection = var.nat_reflection
  description    = "${var.description_prefix} HTTP NAT"

  lifecycle {
    precondition {
      condition     = local.ports_are_distinct
      error_message = "external_http_port, external_https_port, caddy_http_port, and caddy_https_port must all be different."
    }

    precondition {
      condition     = local.caddy_ports_avoid_webui
      error_message = "Caddy listener ports cannot be 80 or 443 because those ports remain assigned to the OPNsense WebUI."
    }
  }
}

resource "opnsense_firewall_nat_port_forward" "https" {
  enabled     = var.enabled
  sequence    = local.https_sequence
  interface   = [var.interface]
  ip_protocol = "inet"
  protocol    = "tcp"
  log         = var.log_nat

  source = {
    net = var.source_network
  }

  destination = {
    net  = local.destination_net
    port = tostring(var.external_https_port)
  }

  target = {
    ip   = "127.0.0.1"
    port = tostring(var.caddy_https_port)
  }

  nat_reflection = var.nat_reflection
  description    = "${var.description_prefix} HTTPS NAT"
}

resource "opnsense_firewall_filter" "http" {
  enabled        = var.enabled
  sequence       = local.http_sequence
  description    = "${var.description_prefix} HTTP filter"
  no_xmlrpc_sync = var.no_xmlrpc_sync

  interface = {
    interface = [var.interface]
  }

  filter = {
    quick       = true
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet"
    protocol    = "TCP"
    log         = var.log_filter

    source = {
      net = var.source_network
    }

    destination = {
      net  = "127.0.0.1"
      port = tostring(var.caddy_http_port)
    }
  }

  stateful_firewall = {
    type = "keep"
  }
}

resource "opnsense_firewall_filter" "https" {
  enabled        = var.enabled
  sequence       = local.https_sequence
  description    = "${var.description_prefix} HTTPS filter"
  no_xmlrpc_sync = var.no_xmlrpc_sync

  interface = {
    interface = [var.interface]
  }

  filter = {
    quick       = true
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet"
    protocol    = "TCP"
    log         = var.log_filter

    source = {
      net = var.source_network
    }

    destination = {
      net  = "127.0.0.1"
      port = tostring(var.caddy_https_port)
    }
  }

  stateful_firewall = {
    type = "keep"
  }
}
