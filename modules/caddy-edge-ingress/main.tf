locals {
  destination_net = var.destination != null ? var.destination : "${var.interface}ip"
  http_sequence   = var.sequence_base
  https_sequence  = var.sequence_base + 1
}

resource "opnsense_firewall_filter" "http" {
  enabled        = var.enabled
  sequence       = local.http_sequence
  description    = "${var.description_prefix} HTTP"
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
    log         = var.log

    source = {
      net = var.source_network
    }

    destination = {
      net  = local.destination_net
      port = tostring(var.http_port)
    }
  }

  stateful_firewall = {
    type = "keep"
  }
}

resource "opnsense_firewall_filter" "https" {
  enabled        = var.enabled
  sequence       = local.https_sequence
  description    = "${var.description_prefix} HTTPS"
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
    log         = var.log

    source = {
      net = var.source_network
    }

    destination = {
      net  = local.destination_net
      port = tostring(var.https_port)
    }
  }

  stateful_firewall = {
    type = "keep"
  }
}
