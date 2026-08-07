output "dedicated_egress_address" {
  description = "Public IPv4 address reserved exclusively for outbound NAT."
  value       = var.dedicated_egress_address
}

output "dedicated_egress_vip_id" {
  description = "UUID of the dedicated egress IP Alias, or null while detached."
  value       = try(opnsense_interfaces_vip.dedicated_egress[0].id, null)
}

output "outbound_nat_enabled" {
  description = "Whether explicit dedicated outbound NAT is managed by this module."
  value       = var.outbound_nat_enabled
}

output "routed_public_subnets" {
  description = "Public workload subnets explicitly excluded from outbound NAT."
  value       = var.routed_public_subnets
}
