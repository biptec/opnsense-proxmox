output "trunk_parent_device" {
  description = "FreeBSD parent device used for Etna tagged VLANs; downstream states use it when creating their own Etna-side VLANs."
  value       = var.trunk_parent_device
}

output "wan_interface" {
  description = "Logical OPNsense interface created for VLAN 3801 WAN."
  value       = opnsense_interfaces_assignment.wan.name
}

output "routed_interfaces" {
  description = "Logical OPNsense interface name for each shared platform-owned routed VLAN."
  value = {
    for name, assignment in opnsense_interfaces_assignment.routed : name => assignment.name
  }
}

output "service_addresses" {
  description = "Stable portable IPv4 service endpoints owned by the platform."
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

output "public_dns_ipv6_address" {
  description = "Dedicated public authoritative DNS IPv6 identity."
  value       = var.wan.public_dns_ipv6_address
}

output "public_proxy_address" {
  description = "Dedicated public reverse-proxy identity."
  value       = var.wan.public_proxy_address
}

output "public_proxy_ipv6_address" {
  description = "Dedicated public reverse-proxy IPv6 identity."
  value       = var.wan.public_proxy_ipv6_address
}

output "dedicated_egress_address" {
  description = "Dedicated Source NAT identity."
  value       = module.router_egress.dedicated_egress_address
}

output "dedicated_egress_ipv6_address" {
  description = "Dedicated stateful NAT66 identity."
  value       = module.router_egress.dedicated_egress_ipv6_address
}

output "routed_public_subnets" {
  description = "Public workload subnets excluded from outbound NAT."
  value       = module.router_egress.routed_public_subnets
}

output "routed_public_ipv6_subnets" {
  description = "Routed-public IPv6 workload subnets excluded from NAT66."
  value       = module.router_egress.routed_public_ipv6_subnets
}

output "trusted_internal_networks" {
  description = "Trusted internal CIDRs used by primary internal-service policy and downstream infrastructure services."
  value       = var.trusted_internal_networks
}

output "dns_zone_name" {
  description = "Authoritative DNS zone name consumed by downstream DNS states."
  value       = var.dns_zone.name
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

output "internal_proxy_address" {
  description = "Portable internal reverse-proxy IPv4 endpoint."
  value       = local.internal_proxy_ipv4
}

output "internal_ntp_address" {
  description = "Portable internal NTP IPv4 endpoint."
  value       = local.internal_ntp_ipv4
}


output "downstream_router_contract" {
  description = "Generic primary-router references consumed by downstream states. Contains no downstream-specific configuration."
  value = {
    trunk_parent_device       = var.trunk_parent_device
    wan_interface             = opnsense_interfaces_assignment.wan.name
    routed_interfaces         = { for name, assignment in opnsense_interfaces_assignment.routed : name => assignment.name }
    routed_public_networks    = var.routed_public_networks
    internal_zone_id          = opnsense_bind_primary_domain.internal.id
    public_zone_id            = opnsense_bind_primary_domain.public.id
    zone_name                 = var.dns_zone.name
    trusted_internal_networks = var.trusted_internal_networks
    internal_dns_ipv4         = local.internal_dns_ipv4
    public_dns_ipv4           = var.wan.public_dns_address
    public_dns_ipv6           = var.wan.public_dns_ipv6_address
    dns_active_service        = opnsense_dns_service_cutover.primary.active_service
  }
}
