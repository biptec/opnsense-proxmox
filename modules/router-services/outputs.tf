output "public_dns_vip_id" {
  description = "UUID of the public DNS IP Alias, or null while the VIP is detached."
  value       = try(opnsense_interfaces_vip.public_dns[0].id, null)
}

output "public_caddy_vip_id" {
  description = "UUID of the public Caddy IP Alias, or null while the VIP is detached."
  value       = try(opnsense_interfaces_vip.public_caddy[0].id, null)
}

output "bind_listener_addresses" {
  description = "Explicit public and internal BIND listener addresses."
  value       = local.bind_listener_addresses
}

output "caddy_listener_addresses" {
  description = "Explicit public and internal Caddy listener addresses."
  value       = local.caddy_listener_addresses
}

output "ntp_service_address" {
  description = "Internal NTP service address served on the dedicated service VLAN interface."
  value       = local.internal_ntp_address
}
