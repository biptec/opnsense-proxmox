locals {
  management_web_ipv4 = split("/", var.management_web_ipv4_cidr)[0]
  management_ssh_ipv6 = var.management_ssh_ipv6_cidr == null ? null : split("/", var.management_ssh_ipv6_cidr)[0]
  management_web_ipv6 = var.management_web_ipv6_cidr == null ? null : split("/", var.management_web_ipv6_cidr)[0]

  internal_ipv4_client_networks = toset([
    for network in var.dns_internal_client_networks : network
    if !strcontains(network, ":")
  ])

  internal_ipv4_interfaces = toset([
    for name, network in var.routed_networks : opnsense_interfaces_assignment.routed[name].name
    if cidrcontains("10.0.0.0/8", network.router_address)
  ])
  internal_service_ingress_interfaces = setunion(
    local.internal_ipv4_interfaces,
    toset([var.management_interface]),
  )
  secondary_public_network_key = try(one([
    for name, network in var.routed_networks : name
    if cidrcontains(network.subnet, var.secondary_dns.public_dns_ipv4)
  ]), null)
  secondary_public_interface = local.secondary_public_network_key == null ? "" : opnsense_interfaces_assignment.routed[local.secondary_public_network_key].name

  firewall_ipv4_rules = {
    management_ssh = {
      enabled     = true
      sequence    = 10
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "TCP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = var.management_ipv4_address
      port        = "22"
      description = "Management SSH endpoint"
    }
    management_web = {
      enabled     = true
      sequence    = 11
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "TCP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = local.management_web_ipv4
      port        = "443"
      description = "Management WebGUI and API endpoint"
    }
    block_web_on_ssh_identity = {
      enabled     = var.cutover.management_endpoint_firewall
      sequence    = 12
      interfaces  = local.internal_service_ingress_interfaces
      action      = "block"
      protocol    = "TCP"
      source      = "any"
      destination = var.management_ipv4_address
      port        = "443"
      description = "Block WebGUI and API on SSH identity"
    }
    block_ssh_on_web_identity = {
      enabled     = var.cutover.management_endpoint_firewall
      sequence    = 13
      interfaces  = local.internal_service_ingress_interfaces
      action      = "block"
      protocol    = "TCP"
      source      = "any"
      destination = local.management_web_ipv4
      port        = "22"
      description = "Block SSH on WebGUI and API identity"
    }
    internal_dns_tcp = {
      enabled     = var.cutover.dns_target == "bind"
      sequence    = 100
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "TCP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = local.internal_dns_ipv4
      port        = "53"
      description = "Internal DNS TCP"
    }
    internal_dns_udp = {
      enabled     = var.cutover.dns_target == "bind"
      sequence    = 101
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "UDP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = local.internal_dns_ipv4
      port        = "53"
      description = "Internal DNS UDP"
    }
    internal_caddy_http = {
      enabled     = var.cutover.caddy_enabled
      sequence    = 110
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "TCP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = local.internal_caddy_ipv4
      port        = "80"
      description = "Internal Caddy HTTP"
    }
    internal_caddy_https = {
      enabled     = var.cutover.caddy_enabled
      sequence    = 111
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "TCP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = local.internal_caddy_ipv4
      port        = "443"
      description = "Internal Caddy HTTPS"
    }
    internal_ntp = {
      enabled     = var.cutover.ntp_serving
      sequence    = 120
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "UDP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = local.internal_ntp_ipv4
      port        = "123"
      description = "Internal NTP"
    }
    rigi_management_ssh = {
      enabled     = var.secondary_dns.enabled
      sequence    = 125
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "TCP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = var.secondary_dns.management_ipv4
      port        = "22"
      description = "Rigi management SSH"
    }
    rigi_internal_dns_tcp = {
      enabled     = var.secondary_dns.enabled && var.cutover.dns_target == "bind"
      sequence    = 126
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "TCP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = var.secondary_dns.internal_dns_ipv4
      port        = "53"
      description = "Rigi internal DNS TCP"
    }
    rigi_internal_dns_udp = {
      enabled     = var.secondary_dns.enabled && var.cutover.dns_target == "bind"
      sequence    = 127
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "UDP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = var.secondary_dns.internal_dns_ipv4
      port        = "53"
      description = "Rigi internal DNS UDP"
    }
    rigi_internal_ntp = {
      enabled     = var.secondary_dns.enabled && var.cutover.ntp_serving
      sequence    = 128
      interfaces  = local.internal_service_ingress_interfaces
      action      = "pass"
      protocol    = "UDP"
      source      = opnsense_firewall_alias.internal_ipv4.name
      destination = var.secondary_dns.internal_ntp_ipv4
      port        = "123"
      description = "Rigi internal NTP"
    }
    rigi_to_primary_public_dns_tcp = {
      enabled     = var.secondary_dns.enabled && var.cutover.dns_target == "bind"
      sequence    = 129
      interfaces  = [local.secondary_public_interface]
      action      = "pass"
      protocol    = "TCP"
      source      = var.secondary_dns.public_dns_ipv4
      destination = var.wan.public_dns_address
      port        = "53"
      description = "Rigi public DNS transfer and refresh TCP"
    }
    rigi_to_primary_public_dns_udp = {
      enabled     = var.secondary_dns.enabled && var.cutover.dns_target == "bind"
      sequence    = 130
      interfaces  = [local.secondary_public_interface]
      action      = "pass"
      protocol    = "UDP"
      source      = var.secondary_dns.public_dns_ipv4
      destination = var.wan.public_dns_address
      port        = "53"
      description = "Rigi public DNS refresh UDP"
    }
    rigi_public_egress = {
      enabled            = var.secondary_dns.enabled
      sequence           = 131
      interfaces         = [local.secondary_public_interface]
      action             = "pass"
      protocol           = "any"
      source             = var.secondary_dns.public_dns_ipv4
      destination        = opnsense_firewall_alias.private_ipv4.name
      destination_invert = true
      port               = ""
      description        = "Rigi routed-public Internet egress without NAT"
    }
    internal_internet_egress = {
      enabled            = var.cutover.outbound_nat
      sequence           = 150
      interfaces         = local.internal_ipv4_interfaces
      action             = "pass"
      protocol           = "any"
      source             = opnsense_firewall_alias.internal_ipv4.name
      destination        = opnsense_firewall_alias.private_ipv4.name
      destination_invert = true
      port               = ""
      description        = "Internal IPv4 Internet egress"
    }
    public_dns_tcp = {
      enabled     = var.cutover.dns_target == "bind"
      sequence    = 200
      interfaces  = [opnsense_interfaces_assignment.wan.name]
      action      = "pass"
      protocol    = "TCP"
      source      = "any"
      destination = var.wan.public_dns_address
      port        = "53"
      description = "Public authoritative DNS TCP"
    }
    public_dns_udp = {
      enabled     = var.cutover.dns_target == "bind"
      sequence    = 201
      interfaces  = [opnsense_interfaces_assignment.wan.name]
      action      = "pass"
      protocol    = "UDP"
      source      = "any"
      destination = var.wan.public_dns_address
      port        = "53"
      description = "Public authoritative DNS UDP"
    }
    public_dns2_tcp = {
      enabled     = var.secondary_dns.enabled && var.cutover.dns_target == "bind"
      sequence    = 202
      interfaces  = [opnsense_interfaces_assignment.wan.name]
      action      = "pass"
      protocol    = "TCP"
      source      = "any"
      destination = var.secondary_dns.public_dns_ipv4
      port        = "53"
      description = "Public secondary authoritative DNS TCP"
    }
    public_dns2_udp = {
      enabled     = var.secondary_dns.enabled && var.cutover.dns_target == "bind"
      sequence    = 203
      interfaces  = [opnsense_interfaces_assignment.wan.name]
      action      = "pass"
      protocol    = "UDP"
      source      = "any"
      destination = var.secondary_dns.public_dns_ipv4
      port        = "53"
      description = "Public secondary authoritative DNS UDP"
    }
    public_caddy_http = {
      enabled     = var.cutover.caddy_enabled
      sequence    = 210
      interfaces  = [opnsense_interfaces_assignment.wan.name]
      action      = "pass"
      protocol    = "TCP"
      source      = "any"
      destination = var.wan.public_caddy_address
      port        = "80"
      description = "Public Caddy HTTP"
    }
    public_caddy_https = {
      enabled     = var.cutover.caddy_enabled
      sequence    = 211
      interfaces  = [opnsense_interfaces_assignment.wan.name]
      action      = "pass"
      protocol    = "TCP"
      source      = "any"
      destination = var.wan.public_caddy_address
      port        = "443"
      description = "Public Caddy HTTPS"
    }
  }

  firewall_ipv6_rules = merge(
    local.management_ssh_ipv6 == null ? {} : {
      management_ssh_ipv6 = {
        enabled     = true
        sequence    = 20
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "TCP"
        source      = "any"
        destination = local.management_ssh_ipv6
        port        = "22"
        description = "Management SSH IPv6 endpoint"
      }
    },
    local.management_web_ipv6 == null ? {} : {
      management_web_ipv6 = {
        enabled     = true
        sequence    = 21
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "TCP"
        source      = "any"
        destination = local.management_web_ipv6
        port        = "443"
        description = "Management WebGUI and API IPv6 endpoint"
      }
    },
    local.management_ssh_ipv6 == null ? {} : {
      block_web_on_ssh_ipv6 = {
        enabled     = var.cutover.management_endpoint_firewall
        sequence    = 22
        interfaces  = local.internal_service_ingress_interfaces
        action      = "block"
        protocol    = "TCP"
        source      = "any"
        destination = local.management_ssh_ipv6
        port        = "443"
        description = "Block WebGUI and API on SSH IPv6 identity"
      }
    },
    local.management_web_ipv6 == null ? {} : {
      block_ssh_on_web_ipv6 = {
        enabled     = var.cutover.management_endpoint_firewall
        sequence    = 23
        interfaces  = local.internal_service_ingress_interfaces
        action      = "block"
        protocol    = "TCP"
        source      = "any"
        destination = local.management_web_ipv6
        port        = "22"
        description = "Block SSH on WebGUI and API IPv6 identity"
      }
    },
    local.internal_dns_ipv6 == null ? {} : {
      internal_dns_tcp_ipv6 = {
        enabled     = var.cutover.dns_target == "bind"
        sequence    = 130
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "TCP"
        source      = "any"
        destination = local.internal_dns_ipv6
        port        = "53"
        description = "Internal DNS TCP IPv6"
      }
      internal_dns_udp_ipv6 = {
        enabled     = var.cutover.dns_target == "bind"
        sequence    = 131
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "UDP"
        source      = "any"
        destination = local.internal_dns_ipv6
        port        = "53"
        description = "Internal DNS UDP IPv6"
      }
    },
    var.secondary_dns.enabled ? {
      rigi_internal_dns_tcp_ipv6 = {
        enabled     = var.cutover.dns_target == "bind"
        sequence    = 135
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "TCP"
        source      = "any"
        destination = var.secondary_dns.internal_dns_ipv6
        port        = "53"
        description = "Rigi internal DNS TCP IPv6"
      }
      rigi_internal_dns_udp_ipv6 = {
        enabled     = var.cutover.dns_target == "bind"
        sequence    = 136
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "UDP"
        source      = "any"
        destination = var.secondary_dns.internal_dns_ipv6
        port        = "53"
        description = "Rigi internal DNS UDP IPv6"
      }
      rigi_internal_ntp_ipv6 = {
        enabled     = var.cutover.ntp_serving
        sequence    = 137
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "UDP"
        source      = "any"
        destination = var.secondary_dns.internal_ntp_ipv6
        port        = "123"
        description = "Rigi internal NTP IPv6"
      }
    } : {},
    local.internal_caddy_ipv6 == null ? {} : {
      internal_caddy_http_ipv6 = {
        enabled     = var.cutover.caddy_enabled
        sequence    = 140
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "TCP"
        source      = "any"
        destination = local.internal_caddy_ipv6
        port        = "80"
        description = "Internal Caddy HTTP IPv6"
      }
      internal_caddy_https_ipv6 = {
        enabled     = var.cutover.caddy_enabled
        sequence    = 141
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "TCP"
        source      = "any"
        destination = local.internal_caddy_ipv6
        port        = "443"
        description = "Internal Caddy HTTPS IPv6"
      }
    },
    local.internal_ntp_ipv6 == null ? {} : {
      internal_ntp_ipv6 = {
        enabled     = var.cutover.ntp_serving
        sequence    = 145
        interfaces  = local.internal_service_ingress_interfaces
        action      = "pass"
        protocol    = "UDP"
        source      = "any"
        destination = local.internal_ntp_ipv6
        port        = "123"
        description = "Internal NTP IPv6"
      }
    },
  )
}

resource "opnsense_firewall_alias" "internal_ipv4" {
  name        = "PLATFORM_INTERNAL_V4"
  type        = "network"
  content     = local.internal_ipv4_client_networks
  description = "Internal IPv4 networks"
}

resource "opnsense_firewall_alias" "private_ipv4" {
  name = "PLATFORM_PRIVATE_V4"
  type = "network"
  content = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
  ]
  description = "RFC1918 IPv4 networks"
}

resource "opnsense_firewall_filter" "platform_ipv4" {
  for_each = local.firewall_ipv4_rules

  enabled     = each.value.enabled
  sequence    = each.value.sequence
  description = each.value.description

  interface = {
    interface = each.value.interfaces
  }

  filter = {
    quick       = true
    action      = each.value.action
    direction   = "in"
    ip_protocol = "inet"
    protocol    = each.value.protocol

    source = {
      net = each.value.source
    }

    destination = {
      invert = try(each.value.destination_invert, false)
      net    = each.value.destination
      port   = each.value.port
    }
  }

  stateful_firewall = {
    type = "keep"
  }

  depends_on = [
    opnsense_dns_service_cutover.primary,
    module.router_egress,
  ]
}

resource "opnsense_firewall_filter" "platform_ipv6" {
  for_each = local.firewall_ipv6_rules

  enabled     = each.value.enabled
  sequence    = each.value.sequence
  description = each.value.description

  interface = {
    interface = each.value.interfaces
  }

  filter = {
    quick       = true
    action      = each.value.action
    direction   = "in"
    ip_protocol = "inet6"
    protocol    = each.value.protocol

    source = {
      net = each.value.source
    }

    destination = {
      net  = each.value.destination
      port = each.value.port
    }
  }

  stateful_firewall = {
    type = "keep"
  }

  depends_on = [
    opnsense_dns_service_cutover.primary,
    module.router_egress,
  ]
}
