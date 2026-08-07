output "wan_interface" {
  description = "Logical OPNsense interface created for VLAN 3801 WAN."
  value       = opnsense_interfaces_assignment.wan.name
}

output "routed_interfaces" {
  description = "Logical OPNsense interface name for each routed VLAN."
  value = {
    for name, assignment in opnsense_interfaces_assignment.routed : name => assignment.name
  }
}

output "service_addresses" {
  description = "Portable IPv4 service endpoints (.2) owned by the platform."
  value       = module.router_foundation.service_addresses
}

output "service_ipv6_addresses" {
  description = "Portable IPv6 service endpoints (::2) for dual-stack services."
  value       = module.router_foundation.service_ipv6_addresses
}

output "service_interfaces" {
  description = "Current OPNsense logical interface for every portable service."
  value       = module.router_foundation.service_interfaces
}

output "public_dns_address" {
  description = "Dedicated public authoritative DNS identity."
  value       = var.wan.public_dns_address
}

output "public_caddy_address" {
  description = "Dedicated public reverse-proxy identity."
  value       = var.wan.public_caddy_address
}

output "dedicated_egress_address" {
  description = "Dedicated Source NAT identity."
  value       = module.router_egress.dedicated_egress_address
}

output "routed_public_subnets" {
  description = "Public workload subnets excluded from outbound NAT."
  value       = module.router_egress.routed_public_subnets
}

output "dns_internal_view_id" {
  description = "BIND internal split-DNS view UUID for dependent site states."
  value       = opnsense_bind_view.internal.id
}

output "dns_public_view_id" {
  description = "BIND public authoritative view UUID for dependent site states."
  value       = opnsense_bind_view.public.id
}

output "dns_internal_zone_id" {
  description = "Internal biptec.net primary-zone UUID for site-owned split-DNS records."
  value       = opnsense_bind_primary_domain.internal.id
}

output "dns_public_zone_id" {
  description = "Public biptec.net primary-zone UUID for site-owned public records."
  value       = opnsense_bind_primary_domain.public.id
}

output "dns_active_service" {
  description = "Observed DNS port owner reported by the guarded cutover resource."
  value       = opnsense_dns_service_cutover.primary.active_service
}

output "internal_dns_address" {
  description = "Portable internal DNS IPv4 endpoint."
  value       = local.internal_dns_ipv4
}

output "internal_caddy_address" {
  description = "Portable internal Caddy IPv4 endpoint."
  value       = local.internal_caddy_ipv4
}

output "internal_ntp_address" {
  description = "Portable internal NTP IPv4 endpoint."
  value       = local.internal_ntp_ipv4
}
