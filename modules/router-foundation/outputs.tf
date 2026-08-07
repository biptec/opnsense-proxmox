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
  description = "Reserved host .1 router gateway used when a service is externalized to its VLAN."
  value       = local.router_addresses
}

output "service_interfaces" {
  description = "Logical OPNsense interface currently hosting each service endpoint: loopback while local, service VLAN after externalization."
  value = {
    for name, assignment in opnsense_interfaces_assignment.service : name => assignment.name
  }
}

output "service_vlan_ids" {
  description = "Reserved VLAN ID for every isolated service network; the VLAN exists only after externalization."
  value = {
    for name, network in var.service_networks : name => network.vlan_id
  }
}

output "service_vlan_devices" {
  description = "Reserved deterministic FreeBSD VLAN device name for every service network; created only after externalization."
  value       = local.service_vlan_devices
}

output "router_hosted_service_addresses" {
  description = "Service host .2 addresses currently assigned with /30 prefixes to dedicated OPNsense loopbacks."
  value = {
    for name, network in local.router_hosted_networks : name => local.service_addresses[name]
  }
}
