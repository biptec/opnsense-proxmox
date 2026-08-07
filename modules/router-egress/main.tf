locals {
  routed_public_nat_rules = {
    for index, subnet in sort(tolist(var.routed_public_subnets)) :
    subnet => var.no_nat_sequence_base + index
  }
}

resource "terraform_data" "address_contract" {
  input = {
    dedicated_egress_address = var.dedicated_egress_address
    service_binding_guard    = var.service_binding_guard
    reserved_addresses       = var.reserved_addresses
    internal_egress_networks = var.internal_egress_networks
    routed_public_subnets    = var.routed_public_subnets
  }

  lifecycle {
    precondition {
      condition     = var.dedicated_egress_address != var.wan_primary_address && !contains(var.reserved_addresses, var.dedicated_egress_address)
      error_message = "The dedicated egress address must not reuse the primary WAN, management, or service addresses."
    }

    precondition {
      condition     = cidrcontains("${var.wan_primary_address}/${var.wan_primary_prefix}", var.wan_gateway)
      error_message = "The WAN gateway must be on-link through the primary WAN prefix."
    }

    precondition {
      condition     = cidrcontains("${var.wan_primary_address}/${var.wan_primary_prefix}", var.dedicated_egress_address)
      error_message = "The dedicated /32 egress alias must be inside the connected primary WAN subnet."
    }

    precondition {
      condition     = !var.public_egress_vip_enabled || trimspace(var.service_binding_guard) != ""
      error_message = "The dedicated egress VIP cannot be attached until the router service-binding layer supplies service_binding_guard."
    }

    precondition {
      condition     = !var.outbound_nat_enabled || var.public_egress_vip_enabled
      error_message = "Outbound NAT cannot be enabled while the dedicated egress VIP is detached."
    }

    precondition {
      condition     = !var.outbound_nat_enabled || length(var.internal_egress_networks) > 0
      error_message = "Outbound NAT requires at least one internal egress network."
    }

    precondition {
      condition     = var.egress_nat_sequence >= var.no_nat_sequence_base + length(var.routed_public_subnets)
      error_message = "egress_nat_sequence must be after the complete routed-public NO-NAT sequence range."
    }
  }
}

resource "opnsense_interfaces_vip" "dedicated_egress" {
  count = var.public_egress_vip_enabled ? 1 : 0

  mode        = "ipalias"
  interface   = var.wan_interface
  network     = "${var.dedicated_egress_address}/32"
  no_bind     = true
  no_expand   = false
  description = "Dedicated outbound NAT address"

  depends_on = [terraform_data.address_contract]
}

resource "opnsense_firewall_nat_settings" "outbound" {
  count = var.outbound_nat_enabled ? 1 : 0
  mode  = "hybrid"

  depends_on = [terraform_data.address_contract]
}

resource "opnsense_firewall_alias" "internal_egress" {
  count = var.outbound_nat_enabled ? 1 : 0

  name        = var.internal_egress_alias_name
  type        = "network"
  content     = var.internal_egress_networks
  description = "Networks using dedicated outbound NAT"
}

resource "opnsense_firewall_nat" "routed_public_no_nat" {
  for_each = var.outbound_nat_enabled ? local.routed_public_nat_rules : {}

  enabled     = true
  disable_nat = true
  sequence    = each.value
  interface   = var.wan_interface
  ip_protocol = "inet"
  protocol    = "any"

  source = {
    net = each.key
  }

  description = "Do not NAT routed public subnet"
  depends_on  = [opnsense_firewall_nat_settings.outbound]
}

resource "opnsense_firewall_nat" "dedicated_egress" {
  count = var.outbound_nat_enabled ? 1 : 0

  enabled     = true
  disable_nat = false
  sequence    = var.egress_nat_sequence
  interface   = var.wan_interface
  ip_protocol = "inet"
  protocol    = "any"

  source = {
    net = opnsense_firewall_alias.internal_egress[0].name
  }

  target = {
    ip = var.dedicated_egress_address
  }

  description = "Internal networks through dedicated egress address"
  depends_on = [
    opnsense_firewall_nat_settings.outbound,
    opnsense_interfaces_vip.dedicated_egress,
  ]
}
