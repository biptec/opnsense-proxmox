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

output "dedicated_egress_ipv6_address" {
  description = "Public IPv6 address reserved exclusively for stateful outbound NAT66."
  value       = var.dedicated_egress_ipv6_address
}

output "dedicated_egress_ipv6_vip_id" {
  description = "UUID of the dedicated IPv6 egress IP Alias, or null while detached."
  value       = try(opnsense_interfaces_vip.dedicated_egress_ipv6[0].id, null)
}

output "routed_public_ipv6_subnets" {
  description = "Routed-public IPv6 workload subnets explicitly excluded from NAT66."
  value       = var.routed_public_ipv6_subnets
}
