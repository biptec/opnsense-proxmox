output "vm_id" {
  description = "Rigi Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.rigi.vm_id
}

output "management_address" {
  description = "Rigi management IPv4 identity."
  value       = local.management_ipv4
}

output "internal_dns_address" {
  description = "Alcor/DNS2 internal IPv4 endpoint."
  value       = local.dns_ipv4
}

output "internal_ntp_address" {
  description = "Kochab/NTP2 internal IPv4 endpoint."
  value       = local.ntp_ipv4
}

output "public_dns_address" {
  description = "Rigi routed-public DNS2 IPv4 endpoint."
  value       = local.public_ipv4
}

output "public_dns_ipv6_address" {
  description = "Rigi routed-public DNS2 IPv6 endpoint."
  value       = local.public_ipv6
}

output "management_vlan" {
  description = "Infrastructure VLAN delivered untagged to Rigi management NIC."
  value       = var.management.vlan_id
}

output "trunk_vlans" {
  description = "Tagged VLANs passed to the Rigi trunk NIC."
  value       = [var.dns_internal.vlan_id, var.ntp_internal.vlan_id, local.public_transport.vlan_id]
}

output "config_revision" {
  description = "Hash driving immutable VM replacement when rendered configuration changes."
  value       = nonsensitive(local.config_revision)
}
