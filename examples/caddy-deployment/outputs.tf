output "public_domain_id" {
  description = "UUID of the public Caddy domain."
  value       = module.public_proxy.domain_id
}

output "internal_domain_id" {
  description = "UUID of the internal Caddy domain."
  value       = module.internal_proxy.domain_id
}

output "internal_dns_override_id" {
  description = "UUID of the Unbound split-DNS record."
  value       = opnsense_unbound_host_override.internal_proxy.id
}

output "public_ingress_destination" {
  description = "Effective public destination matched before DNAT."
  value       = module.public_ingress.destination
}

output "internal_ingress_destination" {
  description = "Dedicated internal service address matched before DNAT."
  value       = module.internal_ingress.destination
}

output "internal_dns_name" {
  description = "Internal FQDN managed by Unbound."
  value       = "${local.internal_hostname}.${local.internal_zone}"
}
