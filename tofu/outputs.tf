# The ID may have been explicitly requested or automatically assigned by Proxmox.
output "vm_id" {
  description = "Actual Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.opnsense.vm_id
}

output "management_ip" {
  description = "IP portion of the first usable IPv4 address reported by QEMU Guest Agent, or null when none is available."
  value       = try(local.reported_ipv4_addresses[0].address, null)
}

output "management_cidr" {
  description = "First usable IPv4 address reported by QEMU Guest Agent in CIDR notation."
  value       = try(local.reported_ipv4_addresses[0].cidr, null)
}

output "management_prefix_length" {
  description = "Prefix length of the first usable IPv4 address reported by QEMU Guest Agent."
  value       = try(local.reported_ipv4_addresses[0].prefix_length, null)
}

output "management_netmask" {
  description = "Dotted-decimal netmask of the first usable IPv4 address reported by QEMU Guest Agent."
  value       = try(local.reported_ipv4_addresses[0].netmask, null)
}

output "ipv4_addresses" {
  description = "Usable guest-reported IPv4 addresses with interface, address, CIDR, prefix length and netmask fields."
  value       = local.reported_ipv4_addresses
}

output "ipv6_addresses" {
  description = "Usable guest-reported IPv6 addresses with interface, address, CIDR and prefix length fields."
  value       = local.reported_ipv6_addresses
}

output "configured_management_ip" {
  description = "IPv4 address requested through Cloud-Init, without the CIDR prefix. This is configuration input, not guest-reported state."
  value       = local.management_ip
}

output "source_image_file_id" {
  description = "Proxmox import file ID used as the source of the VM system disk."
  value       = local.source_image_file_id
}
