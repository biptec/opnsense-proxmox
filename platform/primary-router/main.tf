locals {
  management_ssh_ipv4      = split("/", var.management_ssh_ipv4_cidr)[0]
  management_web_ipv4      = split("/", var.management_web_ipv4_cidr)[0]
  wan_primary_address      = split("/", var.wan.primary_cidr)[0]
  wan_primary_prefix       = tonumber(split("/", var.wan.primary_cidr)[1])
  wan_primary_ipv6_address = split("/", var.wan.primary_ipv6_cidr)[0]
  wan_primary_ipv6_prefix  = tonumber(split("/", var.wan.primary_ipv6_cidr)[1])

  routed_public_subnets = toset([
    for network in values(var.routed_public_networks) : network.subnet
  ])
  routed_public_ipv6_subnets = toset(compact([
    for network in values(var.routed_public_networks) : network.ipv6_subnet
  ]))

  foundation_service_networks = {
    for name, network in var.service_networks : name => {
      vlan_id           = network.vlan_id
      subnet            = network.subnet
      service_ipv4_host = network.service_ipv4_address == cidrhost(network.subnet, 1) ? 1 : 2
      ipv6_subnet       = network.ipv6_subnet
      hosted_on_router  = network.hosted_on_router
    }
  }

  router_services_ipv4 = {
    dns   = module.router_foundation.service_addresses["dns"]
    ntp   = module.router_foundation.service_addresses["ntp"]
    caddy = module.router_foundation.service_addresses["proxy"]
  }
  router_services_ipv6 = length(module.router_foundation.service_ipv6_addresses) == 0 ? {} : {
    dns   = module.router_foundation.service_ipv6_addresses["dns"]
    ntp   = module.router_foundation.service_ipv6_addresses["ntp"]
    caddy = module.router_foundation.service_ipv6_addresses["proxy"]
  }
  router_services_interfaces = {
    for name, interface in module.router_foundation.service_interfaces :
    (name == "proxy" ? "caddy" : name) => interface
  }

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

  routed_vlan_ids  = [for network in values(var.routed_public_networks) : network.vlan_id]
  service_vlan_ids = [for network in values(var.service_networks) : network.vlan_id]
  all_vlan_ids     = concat([var.wan.vlan_id], local.routed_vlan_ids, local.service_vlan_ids)

  current_webgui_certificate_ref = var.webgui_certificate_ref != null ? var.webgui_certificate_ref : try(data.external.current_webgui[0].result.certificate_ref, "")

  reserved_ipv6_addresses = toset(concat(
    [
      local.wan_primary_ipv6_address,
      var.wan.public_dns_ipv6_address,
      var.wan.public_proxy_ipv6_address,
    ],
    values(module.router_foundation.service_ipv6_addresses),
    compact([for network in values(var.routed_public_networks) : network.router_ipv6_address]),
  ))

  reserved_ipv4_addresses = toset(concat(
    [
      local.management_ssh_ipv4,
      local.management_web_ipv4,
      local.wan_primary_address,
      var.wan.public_dns_address,
      var.wan.public_proxy_address,
    ],
    values(module.router_foundation.service_addresses),
    [for network in values(var.routed_public_networks) : network.router_address],
  ))
}

data "external" "current_webgui" {
  count   = var.webgui_certificate_ref == null ? 1 : 0
  program = ["python3", "${path.module}/scripts/read-webgui-certificate.py"]
}

resource "terraform_data" "platform_contract" {
  input = {
    management_vips        = local.management_vips
    wan                    = var.wan
    routed_public_networks = var.routed_public_networks
    service_networks       = local.foundation_service_networks
  }

  lifecycle {
    precondition {
      condition     = length(toset(local.all_vlan_ids)) == length(local.all_vlan_ids)
      error_message = "WAN, routed, and reserved service VLAN IDs must all be unique."
    }

    precondition {
      condition = (
        cidrcontains(var.wan.primary_cidr, var.wan.gateway) &&
        cidrcontains(var.wan.primary_cidr, var.wan.public_dns_address) &&
        cidrcontains(var.wan.primary_cidr, var.wan.public_proxy_address) &&
        cidrcontains(var.wan.primary_cidr, var.wan.dedicated_egress_address)
      )
      error_message = "WAN gateway and all /32 service identities must belong to the connected primary WAN prefix."
    }

    precondition {
      condition = (
        var.wan.ipv6_gateway == "fe80::1" &&
        cidrcontains(var.wan.primary_ipv6_cidr, var.wan.public_dns_ipv6_address) &&
        cidrcontains(var.wan.primary_ipv6_cidr, var.wan.public_proxy_ipv6_address) &&
        cidrcontains(var.wan.primary_ipv6_cidr, var.wan.dedicated_egress_ipv6_address)
      )
      error_message = "WAN IPv6 must use Hetzner link-local gateway fe80::1 and all dedicated IPv6 identities must belong to the connected WAN /64."
    }

    precondition {
      condition = alltrue([
        for network in values(var.routed_public_networks) :
        can(cidrhost(network.subnet, 0)) &&
        try(cidrhost(network.subnet, 0), "") == try(split("/", network.subnet)[0], "invalid") &&
        cidrcontains(network.subnet, network.router_address)
      ])
      error_message = "Every routed IPv4 subnet must be canonical and contain its Etna router address."
    }

    precondition {
      condition = alltrue([
        for network in values(var.routed_public_networks) :
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
      condition     = (var.cutover.dns_target == "bind") == var.cutover.public_dns_vip
      error_message = "The public DNS VIP must be attached exactly when BIND is the selected DNS owner. This prevents wildcard Unbound from being exposed on the public DNS identity."
    }

    precondition {
      condition     = !var.cutover.public_dns_ingress || (var.cutover.dns_target == "bind" && var.cutover.public_dns_vip)
      error_message = "Public DNS WAN ingress requires BIND ownership and the public DNS VIP."
    }

    precondition {
      condition     = !var.cutover.proxy_enabled || var.cutover.public_proxy_vip
      error_message = "The reverse proxy cannot be enabled until its public VIP is attached."
    }

    precondition {
      condition = (
        var.management_ssh_ipv6_cidr == null &&
        var.management_web_ipv6_cidr == null &&
        alltrue([for network in values(var.service_networks) : network.ipv6_subnet == null])
      ) || anytrue([for network in var.trusted_internal_networks : strcontains(network, ":")])
      error_message = "IPv6 management/service endpoints require at least one trusted IPv6 CIDR in trusted_internal_networks."
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
    address = local.wan_primary_address
    prefix  = local.wan_primary_prefix
  }

  ipv6 = {
    mode    = "static"
    address = local.wan_primary_ipv6_address
    prefix  = local.wan_primary_ipv6_prefix
  }
}

resource "opnsense_routing_gateway" "wan" {
  name            = "GW_WAN"
  interface       = opnsense_interfaces_assignment.wan.name
  gateway         = var.wan.gateway
  ip_protocol     = "inet"
  default_gateway = true
  monitor_disable = true
  description     = "Provider WAN IPv4 gateway"
}

resource "opnsense_routing_gateway" "wan_ipv6" {
  name            = "GW_WAN_V6"
  interface       = opnsense_interfaces_assignment.wan.name
  gateway         = var.wan.ipv6_gateway
  ip_protocol     = "inet6"
  default_gateway = true
  monitor_disable = true
  description     = "Provider WAN IPv6 gateway"
}

resource "opnsense_interfaces_vlan" "routed" {
  for_each = var.routed_public_networks

  parent      = var.trunk_parent_device
  tag         = each.value.vlan_id
  priority    = 0
  protocol    = "802.1q"
  device      = "vlan${each.value.vlan_id}"
  description = each.value.description

  depends_on = [terraform_data.platform_contract]
}

resource "opnsense_interfaces_assignment" "routed" {
  for_each = var.routed_public_networks

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

module "router_foundation" {
  source = "../../modules/router-foundation"

  management_interface       = var.management_interface
  management_address         = local.management_ssh_ipv4
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

  service_networks = local.foundation_service_networks

  depends_on = [opnsense_interfaces_vip.management]
}

module "router_services" {
  source = "../../modules/router-services"

  wan_interface             = opnsense_interfaces_assignment.wan.name
  management_address        = module.router_foundation.management_address
  wan_primary_address       = local.wan_primary_address
  wan_primary_prefix        = local.wan_primary_prefix
  wan_gateway               = var.wan.gateway
  api_extensions_plugin_id  = module.router_foundation.api_extensions_plugin_id
  public_dns_address        = var.wan.public_dns_address
  public_dns_ipv6_address   = var.wan.public_dns_ipv6_address
  public_dns_vip_enabled    = var.cutover.public_dns_vip
  public_caddy_address      = var.wan.public_proxy_address
  public_caddy_ipv6_address = var.wan.public_proxy_ipv6_address
  public_caddy_vip_enabled  = var.cutover.public_proxy_vip
  service_addresses         = local.router_services_ipv4
  service_ipv6_addresses    = local.router_services_ipv6
  service_interfaces        = local.router_services_interfaces
  bind_enabled              = null
  caddy_enabled             = var.cutover.proxy_enabled
  ntp_enabled               = true
  ntp_serve_clients         = var.cutover.ntp_serving
  ntp_servers               = var.ntp_servers
}

module "router_egress" {
  source = "../../modules/router-egress"

  wan_interface                 = opnsense_interfaces_assignment.wan.name
  wan_primary_address           = local.wan_primary_address
  wan_primary_prefix            = local.wan_primary_prefix
  wan_primary_ipv6_address      = local.wan_primary_ipv6_address
  wan_primary_ipv6_prefix       = local.wan_primary_ipv6_prefix
  wan_gateway                   = var.wan.gateway
  dedicated_egress_address      = var.wan.dedicated_egress_address
  dedicated_egress_ipv6_address = var.wan.dedicated_egress_ipv6_address
  reserved_addresses            = local.reserved_ipv4_addresses
  reserved_ipv6_addresses       = local.reserved_ipv6_addresses
  service_binding_guard         = module.router_services.service_binding_guard
  public_egress_vip_enabled     = var.cutover.egress_vip
  outbound_nat_enabled          = var.cutover.outbound_nat
  internal_egress_networks      = var.internal_egress_networks
  internal_egress_ipv6_networks = var.internal_egress_ipv6_networks
  routed_public_subnets         = local.routed_public_subnets
  routed_public_ipv6_subnets    = local.routed_public_ipv6_subnets
}
