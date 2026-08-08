locals {
  router_networks = {
    management = {
      vlan_id      = var.management.vlan_id
      ipv4_cidr    = var.management.ipv4_cidr
      ipv4_gateway = var.management.ipv4_gateway
      ipv6_cidr    = var.management.ipv6_cidr
      ipv6_gateway = var.management.ipv6_gateway
      description  = "Rigi host management"
    }
    dns = {
      vlan_id      = var.dns_internal.vlan_id
      ipv4_cidr    = var.dns_internal.ipv4_cidr
      ipv4_gateway = var.dns_internal.ipv4_gateway
      ipv6_cidr    = var.dns_internal.ipv6_cidr
      ipv6_gateway = var.dns_internal.ipv6_gateway
      description  = "Alcor secondary DNS"
    }
    ntp = {
      vlan_id      = var.ntp_internal.vlan_id
      ipv4_cidr    = var.ntp_internal.ipv4_cidr
      ipv4_gateway = var.ntp_internal.ipv4_gateway
      ipv6_cidr    = var.ntp_internal.ipv6_cidr
      ipv6_gateway = var.ntp_internal.ipv6_gateway
      description  = "Kochab secondary NTP"
    }
  }

  router_private_ipv4  = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  router_internal_ipv4 = sort([for network in var.primary_router.trusted_internal_networks : network if !strcontains(network, ":")])
  router_internal_ipv6 = sort([for network in var.primary_router.trusted_internal_networks : network if strcontains(network, ":")])

  router_firewall_rules = {
    management_ssh = {
      sequence         = 290
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = true
      protocol         = "TCP"
      source           = opnsense_firewall_alias.rigi_internal_ipv4.name
      destination      = local.management_ipv4
      port             = "22"
      invert           = false
      description      = "Rigi management SSH from trusted internal networks"
    }
    internal_dns_tcp = {
      sequence         = 291
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = true
      protocol         = "TCP"
      source           = opnsense_firewall_alias.rigi_internal_ipv4.name
      destination      = local.dns_ipv4
      port             = "53"
      invert           = false
      description      = "Rigi internal DNS TCP"
    }
    internal_dns_udp = {
      sequence         = 292
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = true
      protocol         = "UDP"
      source           = opnsense_firewall_alias.rigi_internal_ipv4.name
      destination      = local.dns_ipv4
      port             = "53"
      invert           = false
      description      = "Rigi internal DNS UDP"
    }
    internal_ntp = {
      sequence         = 293
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = true
      protocol         = "UDP"
      source           = opnsense_firewall_alias.rigi_internal_ipv4.name
      destination      = local.ntp_ipv4
      port             = "123"
      invert           = false
      description      = "Rigi internal NTP"
    }
    dns_to_primary_tcp = {
      sequence    = 300
      interfaces  = [opnsense_interfaces_assignment.rigi["dns"].name]
      protocol    = "TCP"
      source      = local.dns_ipv4
      destination = var.primary_router.internal_dns_ipv4
      port        = "53"
      invert      = false
      description = "Rigi DNS2 transfer to primary internal DNS"
    }
    dns_to_primary_udp = {
      sequence    = 301
      interfaces  = [opnsense_interfaces_assignment.rigi["dns"].name]
      protocol    = "UDP"
      source      = local.dns_ipv4
      destination = var.primary_router.internal_dns_ipv4
      port        = "53"
      invert      = false
      description = "Rigi DNS2 refresh from primary internal DNS"
    }
    public_to_primary_tcp = {
      sequence    = 302
      interfaces  = [var.primary_router.routed_interfaces["public_transport"]]
      protocol    = "TCP"
      source      = local.public_ipv4
      destination = var.primary_router.public_dns_ipv4
      port        = "53"
      invert      = false
      description = "Rigi DNS2 transfer to primary public DNS"
    }
    public_to_primary_udp = {
      sequence    = 303
      interfaces  = [var.primary_router.routed_interfaces["public_transport"]]
      protocol    = "UDP"
      source      = local.public_ipv4
      destination = var.primary_router.public_dns_ipv4
      port        = "53"
      invert      = false
      description = "Rigi DNS2 refresh from primary public DNS"
    }
    public_dns2_tcp = {
      enabled     = var.public_dns_ingress
      sequence    = 304
      interfaces  = [var.primary_router.wan_interface]
      protocol    = "TCP"
      source      = "any"
      destination = local.public_ipv4
      port        = "53"
      invert      = false
      description = "Public secondary authoritative DNS TCP"
    }
    public_dns2_udp = {
      enabled     = var.public_dns_ingress
      sequence    = 305
      interfaces  = [var.primary_router.wan_interface]
      protocol    = "UDP"
      source      = "any"
      destination = local.public_ipv4
      port        = "53"
      invert      = false
      description = "Public secondary authoritative DNS UDP"
    }
    dns_internet_egress = {
      sequence    = 306
      interfaces  = [opnsense_interfaces_assignment.rigi["dns"].name]
      protocol    = "any"
      source      = local.dns_ipv4
      destination = opnsense_firewall_alias.rigi_private_ipv4.name
      port        = ""
      invert      = true
      description = "Rigi DNS2 recursive Internet egress"
    }
    ntp_internet_egress = {
      sequence    = 307
      interfaces  = [opnsense_interfaces_assignment.rigi["ntp"].name]
      protocol    = "any"
      source      = local.ntp_ipv4
      destination = opnsense_firewall_alias.rigi_private_ipv4.name
      port        = ""
      invert      = true
      description = "Rigi NTP2 Internet egress"
    }
    public_internet_egress = {
      sequence    = 308
      interfaces  = [var.primary_router.routed_interfaces["public_transport"]]
      protocol    = "any"
      source      = local.public_ipv4
      destination = opnsense_firewall_alias.rigi_private_ipv4.name
      port        = ""
      invert      = true
      description = "Rigi routed-public Internet egress without NAT"
    }
  }
}

resource "opnsense_interfaces_vlan" "rigi" {
  for_each = local.router_networks

  parent      = var.primary_router.trunk_parent_device
  tag         = each.value.vlan_id
  priority    = 0
  protocol    = "802.1q"
  device      = "vlan${each.value.vlan_id}"
  description = each.value.description
}

resource "opnsense_interfaces_assignment" "rigi" {
  for_each = local.router_networks

  device            = opnsense_interfaces_vlan.rigi[each.key].device
  description       = each.value.description
  enabled           = true
  allow_readdress   = var.allow_router_readdress
  locked            = false
  gateway_interface = false
  block_private     = false
  block_bogons      = false

  ipv4 = {
    mode    = "static"
    address = each.value.ipv4_gateway
    prefix  = tonumber(split("/", each.value.ipv4_cidr)[1])
  }

  ipv6 = {
    mode    = "static"
    address = each.value.ipv6_gateway
    prefix  = tonumber(split("/", each.value.ipv6_cidr)[1])
  }
}

resource "opnsense_bind_tsig_key" "secondary_transfer" {
  name      = var.transfer_tsig_name
  algorithm = var.transfer_tsig_algorithm
  secret    = var.transfer_tsig_secret
  enabled   = true
}

# Publish secondary-zone integration only after the immutable Rigi VM is ready.
# NS2 records depend on these attachments, so destroy reverses safely:
# NS2 records -> transfer detach -> VM -> Etna VLAN/firewall cleanup.
resource "opnsense_bind_primary_domain_transfer" "internal" {
  domain_id       = var.primary_router.internal_zone_id
  transfer_key_id = opnsense_bind_tsig_key.secondary_transfer.id
  also_notify     = [local.dns_ipv4]


  depends_on = [proxmox_virtual_environment_vm.rigi]
}

resource "opnsense_bind_primary_domain_transfer" "public" {
  domain_id       = var.primary_router.public_zone_id
  transfer_key_id = opnsense_bind_tsig_key.secondary_transfer.id
  also_notify     = [local.public_ipv4]


  depends_on = [proxmox_virtual_environment_vm.rigi]
}

resource "opnsense_bind_record" "internal_ns2" {
  domain_id = var.primary_router.internal_zone_id
  name      = "@"
  type      = "NS"
  value     = "ns2.${trimsuffix(var.primary_router.zone_name, ".")}."


  depends_on = [opnsense_bind_primary_domain_transfer.internal]
}

resource "opnsense_bind_record" "internal_ns2_ipv4" {
  domain_id = var.primary_router.internal_zone_id
  name      = "ns2"
  type      = "A"
  value     = local.dns_ipv4


  depends_on = [opnsense_bind_primary_domain_transfer.internal]
}

resource "opnsense_bind_record" "internal_ns2_ipv6" {
  domain_id = var.primary_router.internal_zone_id
  name      = "ns2"
  type      = "AAAA"
  value     = local.dns_ipv6


  depends_on = [opnsense_bind_primary_domain_transfer.internal]
}

resource "opnsense_bind_record" "public_ns2" {
  domain_id = var.primary_router.public_zone_id
  name      = "@"
  type      = "NS"
  value     = "ns2.${trimsuffix(var.primary_router.zone_name, ".")}."


  depends_on = [opnsense_bind_primary_domain_transfer.public]
}

resource "opnsense_bind_record" "public_ns2_ipv4" {
  domain_id = var.primary_router.public_zone_id
  name      = "ns2"
  type      = "A"
  value     = local.public_ipv4


  depends_on = [opnsense_bind_primary_domain_transfer.public]
}

resource "opnsense_bind_record" "public_ns2_ipv6" {
  domain_id = var.primary_router.public_zone_id
  name      = "ns2"
  type      = "AAAA"
  value     = local.public_ipv6

  depends_on = [opnsense_bind_primary_domain_transfer.public]
}

resource "opnsense_firewall_alias" "rigi_private_ipv4" {
  name        = "RIGI_PRIVATE_V4"
  type        = "network"
  content     = local.router_private_ipv4
  description = "RFC1918 destinations excluded from Rigi Internet egress rules"
}

resource "opnsense_firewall_alias" "rigi_internal_ipv4" {
  name        = "RIGI_INTERNAL_V4"
  type        = "network"
  content     = local.router_internal_ipv4
  description = "Trusted IPv4 clients allowed to reach Rigi services"
}

resource "opnsense_firewall_alias" "rigi_internal_ipv6" {
  name        = "RIGI_INTERNAL_V6"
  type        = "network"
  content     = local.router_internal_ipv6
  description = "Trusted IPv6 clients allowed to reach Rigi services"
}

resource "opnsense_firewall_filter" "rigi" {
  for_each = local.router_firewall_rules

  enabled     = try(each.value.enabled, true)
  sequence    = each.value.sequence
  description = each.value.description

  interface = {
    invert    = try(each.value.interface_invert, false)
    interface = each.value.interfaces
  }

  filter = {
    quick       = true
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet"
    protocol    = each.value.protocol

    source = {
      net = each.value.source
    }

    destination = {
      invert = each.value.invert
      net    = each.value.destination
      port   = each.value.port
    }
  }

  stateful_firewall = {
    type = "keep"
  }
}


locals {
  router_firewall_ipv6_rules = {
    management_ssh = {
      sequence         = 390
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = true
      protocol         = "TCP"
      source           = opnsense_firewall_alias.rigi_internal_ipv6.name
      destination      = local.management_ipv6
      port             = "22"
      invert           = false
      description      = "Rigi management SSH IPv6 from trusted internal networks"
    }
    internal_dns_tcp = {
      sequence         = 391
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = true
      protocol         = "TCP"
      source           = opnsense_firewall_alias.rigi_internal_ipv6.name
      destination      = local.dns_ipv6
      port             = "53"
      invert           = false
      description      = "Rigi internal DNS TCP IPv6"
    }
    internal_dns_udp = {
      sequence         = 392
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = true
      protocol         = "UDP"
      source           = opnsense_firewall_alias.rigi_internal_ipv6.name
      destination      = local.dns_ipv6
      port             = "53"
      invert           = false
      description      = "Rigi internal DNS UDP IPv6"
    }
    internal_ntp = {
      sequence         = 393
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = true
      protocol         = "UDP"
      source           = opnsense_firewall_alias.rigi_internal_ipv6.name
      destination      = local.ntp_ipv6
      port             = "123"
      invert           = false
      description      = "Rigi internal NTP IPv6"
    }
    public_dns2_tcp = {
      enabled          = var.public_dns_ingress
      sequence         = 394
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = false
      protocol         = "TCP"
      source           = "any"
      destination      = local.public_ipv6
      port             = "53"
      invert           = false
      description      = "Public secondary authoritative DNS TCP IPv6"
    }
    public_dns2_udp = {
      enabled          = var.public_dns_ingress
      sequence         = 395
      interfaces       = [var.primary_router.wan_interface]
      interface_invert = false
      protocol         = "UDP"
      source           = "any"
      destination      = local.public_ipv6
      port             = "53"
      invert           = false
      description      = "Public secondary authoritative DNS UDP IPv6"
    }
    dns_internet_egress = {
      sequence         = 396
      interfaces       = [opnsense_interfaces_assignment.rigi["dns"].name]
      interface_invert = false
      protocol         = "any"
      source           = local.dns_ipv6
      destination      = opnsense_firewall_alias.rigi_internal_ipv6.name
      port             = ""
      invert           = true
      description      = "Rigi DNS2 IPv6 Internet egress through NAT66"
    }
    ntp_internet_egress = {
      sequence         = 397
      interfaces       = [opnsense_interfaces_assignment.rigi["ntp"].name]
      interface_invert = false
      protocol         = "any"
      source           = local.ntp_ipv6
      destination      = opnsense_firewall_alias.rigi_internal_ipv6.name
      port             = ""
      invert           = true
      description      = "Rigi NTP2 IPv6 Internet egress through NAT66"
    }
    public_internet_egress = {
      sequence         = 398
      interfaces       = [var.primary_router.routed_interfaces["public_transport"]]
      interface_invert = false
      protocol         = "any"
      source           = local.public_ipv6
      destination      = opnsense_firewall_alias.rigi_internal_ipv6.name
      port             = ""
      invert           = true
      description      = "Rigi routed-public IPv6 Internet egress without NAT"
    }
  }
}

resource "opnsense_firewall_filter" "rigi_ipv6" {
  for_each = local.router_firewall_ipv6_rules

  enabled     = try(each.value.enabled, true)
  sequence    = each.value.sequence
  description = each.value.description

  interface = {
    invert    = each.value.interface_invert
    interface = each.value.interfaces
  }

  filter = {
    quick       = true
    action      = "pass"
    direction   = "in"
    ip_protocol = "inet6"
    protocol    = each.value.protocol

    source = {
      net = each.value.source
    }

    destination = {
      invert = each.value.invert
      net    = each.value.destination
      port   = each.value.port
    }
  }

  stateful_firewall = {
    type = "keep"
  }
}
