output "domain_ids" {
  description = "Caddy domain UUIDs keyed by application FQDN."
  value       = { for domain, route in module.route : domain => route.domain_id }
}

output "handler_ids" {
  description = "Caddy handler UUIDs keyed by application FQDN."
  value       = { for domain, route in module.route : domain => route.handler_id }
}

output "certificate_ref_ids" {
  description = "Selected or generated certificate references keyed by FQDN."
  value       = { for domain, route in module.route : domain => route.certificate_ref_id }
}

output "unbound_record_ids" {
  description = "Optional Unbound record UUIDs keyed by internal FQDN."
  value       = { for domain, record in opnsense_unbound_host_override.route : domain => record.id }
}
