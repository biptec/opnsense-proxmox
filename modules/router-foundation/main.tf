locals {
  service_addresses = {
    for name, network in var.service_networks : name => cidrhost(network.subnet, 2)
  }
  router_addresses = {
    for name, network in var.service_networks : name => cidrhost(network.subnet, 1)
  }
  router_hosted_networks = {
    for name, network in var.service_networks : name => network
    if network.hosted_on_router
  }
  externalized_networks = {
    for name, network in var.service_networks : name => network
    if !network.hosted_on_router
  }
  service_vlan_devices = {
    for name, network in var.service_networks : name => "vlan${network.vlan_id}"
  }
}

resource "terraform_data" "address_contract" {
  input = {
    management_address = var.management_address
    service_networks   = var.service_networks
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for network in values(var.service_networks) :
        !cidrcontains(network.subnet, var.management_address)
      ])
      error_message = "The management address must not belong to a service /30."
    }
  }
}

resource "opnsense_plugin" "api_extensions" {
  name                 = "os-api-extensions"
  uninstall_on_destroy = false
}

resource "opnsense_system_webgui" "management" {
  protocol                = var.webgui.protocol
  port                    = var.webgui.port
  interfaces              = [var.management_interface]
  certificate_ref         = var.webgui.certificate_ref
  session_timeout_minutes = var.webgui.session_timeout_minutes
  hsts                    = var.webgui.hsts
  disable_http_redirect   = var.webgui.disable_http_redirect
  alternate_hostnames     = var.webgui.alternate_hostnames
  allow_readdress         = var.allow_management_readdress

  depends_on = [opnsense_plugin.api_extensions]
}

resource "opnsense_system_ssh" "management" {
  enabled                 = var.ssh.enabled
  port                    = var.ssh.port
  interfaces              = [var.management_interface]
  password_authentication = var.ssh.password_authentication
  permit_root_login       = var.ssh.permit_root_login
  allow_readdress         = var.allow_management_readdress

  depends_on = [opnsense_plugin.api_extensions]
}

resource "opnsense_interfaces_loopback" "service" {
  for_each = local.router_hosted_networks

  description = "${title(replace(each.key, "_", " "))} local service network"

  depends_on = [terraform_data.address_contract]
}

resource "opnsense_interfaces_vlan" "service" {
  for_each = local.externalized_networks

  parent      = var.trunk_parent_device
  tag         = each.value.vlan_id
  priority    = 0
  protocol    = "802.1q"
  device      = local.service_vlan_devices[each.key]
  description = "${title(replace(each.key, "_", " "))} service VLAN"

  depends_on = [terraform_data.address_contract]
}

resource "opnsense_interfaces_assignment" "service" {
  for_each = var.service_networks

  device            = each.value.hosted_on_router ? format("lo%d", opnsense_interfaces_loopback.service[each.key].device_id) : opnsense_interfaces_vlan.service[each.key].device
  description       = each.value.hosted_on_router ? "${title(replace(each.key, "_", " "))} local service" : "${title(replace(each.key, "_", " "))} service gateway"
  enabled           = true
  allow_readdress   = var.allow_service_readdress
  locked            = false
  gateway_interface = false
  block_private     = false
  block_bogons      = false

  ipv4 = {
    mode    = "static"
    address = each.value.hosted_on_router ? local.service_addresses[each.key] : local.router_addresses[each.key]
    prefix  = 30
  }

  ipv6 = {
    mode = "none"
  }
}
