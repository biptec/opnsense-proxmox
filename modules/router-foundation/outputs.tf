output "management_address" {
  description = "Management IPv4 address reserved outside all service networks."
  value       = var.management_address
}

output "api_extensions_plugin_id" {
  description = "Dependency token proving that os-api-extensions is installed."
  value       = opnsense_plugin.api_extensions.id
}

output "management_interface" {
  description = "Logical interface exclusively owned by WebGUI/API and SSH."
  value       = var.management_interface
}

output "service_addresses" {
  description = "Portable host .2 address for every service /30."
  value       = local.service_addresses
}

output "router_addresses" {
  description = "Permanent host .1 router gateway for every service VLAN."
  value       = local.router_addresses
}

output "service_interfaces" {
  description = "Logical OPNsense interface allocated to every service VLAN."
  value = {
    for name, assignment in opnsense_interfaces_assignment.service : name => assignment.name
  }
}

output "service_vlan_ids" {
  description = "VLAN ID allocated to every isolated service network."
  value = {
    for name, network in var.service_networks : name => network.vlan_id
  }
}

output "service_vlan_devices" {
  description = "Deterministic FreeBSD VLAN device allocated to every service network."
  value       = local.service_vlan_devices
}

output "router_hosted_service_addresses" {
  description = "Service addresses currently held as IP Alias VIPs by OPNsense."
  value = {
    for name, network in local.router_hosted_networks : name => local.service_addresses[name]
  }
}
