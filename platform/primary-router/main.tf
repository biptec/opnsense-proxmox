locals {
  management_vips = merge(
    {
      web_ipv4 = {
        network     = var.management_web_ipv4_cidr
        description = "WebGUI and API management IPv4"
      }
    },
    var.management_ssh_ipv6_cidr == null ? {} : {
      ssh_ipv6 = {
        network     = var.management_ssh_ipv6_cidr
        description = "SSH management IPv6"
      }
    },
    var.management_web_ipv6_cidr == null ? {} : {
      web_ipv6 = {
        network     = var.management_web_ipv6_cidr
        description = "WebGUI and API management IPv6"
      }
    },
  )

  routed_vlan_ids  = [for network in values(var.routed_networks) : network.vlan_id]
  service_vlan_ids = [for network in values(var.service_networks) : network.vlan_id]
  all_vlan_ids     = concat([var.wan.vlan_id], local.routed_vlan_ids, local.service_vlan_ids)

  current_webgui_certificate_ref = var.webgui_certificate_ref != null ? var.webgui_certificate_ref : try(data.external.current_webgui[0].result.certificate_ref, "")

  reserved_ipv4_addresses = toset(concat(
    [
      var.management_ipv4_address,
      split("/", var.management_web_ipv4_cidr)[0],
      var.wan.primary_address,
      var.wan.public_dns_address,
      var.wan.public_caddy_address,
    ],
    values(module.router_foundation.service_addresses),
    [for network in values(var.routed_networks) : network.router_address],
  ))
}

data "external" "current_webgui" {
  count   = var.webgui_certificate_ref == null ? 1 : 0
  program = ["python3", "${path.module}/scripts/read-webgui-certificate.py"]
}

resource "terraform_data" "platform_contract" {
  input = {
    management_vips  = local.management_vips
    wan              = var.wan
    routed_networks  = var.routed_networks
    service_networks = var.service_networks
  }

  lifecycle {
    precondition {
      condition     = length(toset(local.all_vlan_ids)) == length(local.all_vlan_ids)
      error_message = "WAN, routed, and reserved service VLAN IDs must all be unique."
    }

    precondition {
      condition = (
        cidrcontains("${var.wan.primary_address}/${var.wan.primary_prefix}", var.wan.gateway) &&
        cidrcontains("${var.wan.primary_address}/${var.wan.primary_prefix}", var.wan.public_dns_address) &&
        cidrcontains("${var.wan.primary_address}/${var.wan.primary_prefix}", var.wan.public_caddy_address) &&
        cidrcontains("${var.wan.primary_address}/${var.wan.primary_prefix}", var.wan.dedicated_egress_address)
      )
      error_message = "WAN gateway and all /32 service identities must belong to the connected primary WAN prefix."
    }

    precondition {
      condition = alltrue([
        for network in values(var.routed_networks) :
        can(cidrhost(network.subnet, 0)) &&
        try(cidrhost(network.subnet, 0), "") == try(split("/", network.subnet)[0], "invalid") &&
        cidrcontains(network.subnet, network.router_address)
      ])
      error_message = "Every routed IPv4 subnet must be canonical and contain its Etna router address."
    }

    precondition {
      condition = alltrue([
        for network in values(var.routed_networks) :
        (network.ipv6_subnet == null && network.router_ipv6_address == null) ||
        (
          network.ipv6_subnet != null && network.router_ipv6_address != null &&
          can(cidrhost(network.ipv6_subnet, 0)) &&
          strcontains(network.ipv6_subnet, ":") &&
          cidrcontains(network.ipv6_subnet, network.router_ipv6_address)
        )
      ])
      error_message = "Routed IPv6 subnet and Etna address must be supplied together and the address must belong to the subnet."
    }

    precondition {
      condition = (
        contains(keys(var.routed_networks), var.vpn_client_route.via_network_key) &&
        cidrcontains(var.routed_networks[var.vpn_client_route.via_network_key].subnet, var.vpn_client_route.gateway_address)
      )
      error_message = "The VPN client route gateway must belong to its selected downstream routed network."
    }

    precondition {
      condition     = (var.cutover.dns_target == "bind") == var.cutover.public_dns_vip
      error_message = "The public DNS VIP must be attached exactly when BIND is the selected DNS owner. This prevents wildcard Unbound from being exposed on the public DNS identity."
    }

    precondition {
      condition     = !var.cutover.caddy_enabled || var.cutover.public_caddy_vip
      error_message = "Caddy cannot be enabled until its public VIP is attached."
    }

    precondition {
      condition = !var.secondary_dns.enabled || (
        try(trimspace(var.secondary_transfer_tsig_secret), "") != "" &&
        try(can(base64decode(var.secondary_transfer_tsig_secret)), false)
      )
      error_message = "secondary_dns.enabled requires a non-empty Base64 secondary_transfer_tsig_secret."
    }

    precondition {
      condition = !var.secondary_dns.enabled || alltrue([
        for address in [
          var.secondary_dns.management_ipv4,
          var.secondary_dns.internal_dns_ipv4,
          var.secondary_dns.internal_ntp_ipv4,
          var.secondary_dns.public_dns_ipv4,
          ] : anytrue([
            for network in values(var.routed_networks) : cidrcontains(network.subnet, address)
        ])
      ])
      error_message = "Rigi secondary identities must remain inside the routed host, DNS2, NTP2, and public transport networks."
    }

    precondition {
      condition     = trimspace(local.current_webgui_certificate_ref) != ""
      error_message = "A current WebGUI certificate reference must be discoverable or explicitly supplied."
    }
  }
}

resource "opnsense_interfaces_vip" "management" {
  for_each = local.management_vips

  mode        = "ipalias"
  interface   = var.management_interface
  network     = each.value.network
  no_bind     = false
  no_expand   = false
  description = each.value.description

  depends_on = [terraform_data.platform_contract]
}

resource "opnsense_interfaces_vlan" "wan" {
  parent      = var.trunk_parent_device
  tag         = var.wan.vlan_id
  priority    = 0
  protocol    = "802.1q"
  device      = "vlan${var.wan.vlan_id}"
  description = "WAN transport"

  depends_on = [terraform_data.platform_contract]
}

resource "opnsense_interfaces_assignment" "wan" {
  device            = opnsense_interfaces_vlan.wan.device
  description       = "WAN"
  enabled           = true
  allow_readdress   = var.allow_network_readdress
  locked            = false
  gateway_interface = true
  block_private     = false
  block_bogons      = false

  ipv4 = {
    mode    = "static"
    address = var.wan.primary_address
    prefix  = var.wan.primary_prefix
  }

  ipv6 = {
    mode = "none"
  }
}

resource "opnsense_routing_gateway" "wan" {
  name            = "GW_WAN"
  interface       = opnsense_interfaces_assignment.wan.name
  gateway         = var.wan.gateway
  ip_protocol     = "inet"
  default_gateway = true
  monitor_disable = true
  description     = "Provider WAN gateway"
}

resource "opnsense_interfaces_vlan" "routed" {
  for_each = var.routed_networks

  parent      = var.trunk_parent_device
  tag         = each.value.vlan_id
  priority    = 0
  protocol    = "802.1q"
  device      = "vlan${each.value.vlan_id}"
  description = each.value.description

  depends_on = [terraform_data.platform_contract]
}

resource "opnsense_interfaces_assignment" "routed" {
  for_each = var.routed_networks

  device            = opnsense_interfaces_vlan.routed[each.key].device
  description       = each.value.description
  enabled           = true
  allow_readdress   = var.allow_network_readdress
  locked            = false
  gateway_interface = false
  block_private     = false
  block_bogons      = false

  ipv4 = {
    mode    = "static"
    address = each.value.router_address
    prefix  = tonumber(split("/", each.value.subnet)[1])
  }

  ipv6 = {
    mode    = each.value.ipv6_subnet == null ? "none" : "static"
    address = each.value.router_ipv6_address
    prefix  = each.value.ipv6_subnet == null ? null : tonumber(split("/", each.value.ipv6_subnet)[1])
  }
}

resource "opnsense_routing_gateway" "vpn_clients" {
  name            = var.vpn_client_route.gateway_name
  interface       = opnsense_interfaces_assignment.routed[var.vpn_client_route.via_network_key].name
  gateway         = var.vpn_client_route.gateway_address
  ip_protocol     = "inet"
  default_gateway = false
  monitor_disable = true
  description     = "VPN client network next hop"
}

resource "opnsense_route" "vpn_clients" {
  gateway     = opnsense_routing_gateway.vpn_clients.name
  network     = var.vpn_client_route.network
  description = "VPN client network"
}

module "router_foundation" {
  source = "../../modules/router-foundation"

  management_interface       = var.management_interface
  management_address         = var.management_ipv4_address
  trunk_parent_device        = var.trunk_parent_device
  reserved_vlan_ids          = toset(concat([var.wan.vlan_id], local.routed_vlan_ids))
  allow_management_readdress = var.allow_management_readdress
  allow_service_readdress    = var.allow_service_readdress

  webgui = {
    protocol            = "https"
    port                = 443
    certificate_ref     = local.current_webgui_certificate_ref
    hsts                = true
    alternate_hostnames = ["web.etna.host.biptec.net"]
  }

  ssh = {
    enabled                 = true
    port                    = 22
    password_authentication = false
    permit_root_login       = false
  }

  service_networks = var.service_networks

  depends_on = [opnsense_interfaces_vip.management]
}

module "router_services" {
  source = "../../modules/router-services"

  wan_interface            = opnsense_interfaces_assignment.wan.name
  management_address       = module.router_foundation.management_address
  wan_primary_address      = var.wan.primary_address
  wan_primary_prefix       = var.wan.primary_prefix
  wan_gateway              = var.wan.gateway
  api_extensions_plugin_id = module.router_foundation.api_extensions_plugin_id
  public_dns_address       = var.wan.public_dns_address
  public_dns_vip_enabled   = var.cutover.public_dns_vip
  public_caddy_address     = var.wan.public_caddy_address
  public_caddy_vip_enabled = var.cutover.public_caddy_vip
  service_addresses        = module.router_foundation.service_addresses
  service_ipv6_addresses   = module.router_foundation.service_ipv6_addresses
  service_interfaces       = module.router_foundation.service_interfaces
  bind_enabled             = null
  caddy_enabled            = var.cutover.caddy_enabled
  ntp_enabled              = true
  ntp_serve_clients        = var.cutover.ntp_serving
  ntp_servers              = var.ntp_servers
}

module "router_egress" {
  source = "../../modules/router-egress"

  wan_interface             = opnsense_interfaces_assignment.wan.name
  wan_primary_address       = var.wan.primary_address
  wan_primary_prefix        = var.wan.primary_prefix
  wan_gateway               = var.wan.gateway
  dedicated_egress_address  = var.wan.dedicated_egress_address
  reserved_addresses        = local.reserved_ipv4_addresses
  service_binding_guard     = module.router_services.service_binding_guard
  public_egress_vip_enabled = var.cutover.egress_vip
  outbound_nat_enabled      = var.cutover.outbound_nat
  internal_egress_networks  = var.internal_egress_networks
  routed_public_subnets     = var.routed_public_subnets
}
