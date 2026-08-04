output "domain_id" {
  description = "UUID of the managed Caddy domain."
  value       = opnsense_caddy_domain.this.id
}

output "handler_id" {
  description = "UUID of the managed Caddy handler."
  value       = opnsense_caddy_handler.this.id
}

output "access_list_id" {
  description = "UUID of the generated or referenced Caddy access list, or an empty string when none is configured."
  value       = local.effective_access_list_id
}

output "certificate_ref_id" {
  description = "OPNsense certificate reference ID selected or dynamically generated for the domain."
  value       = opnsense_caddy_domain.this.certificate_ref_id
}

output "generated_certificate_id" {
  description = "UUID of the leaf certificate owned by the domain resource in internal mode."
  value       = opnsense_caddy_domain.this.generated_certificate_id
}

output "preserve_host_header_id" {
  description = "UUID of the generated Host-preservation header, or an empty string when preserve_host is false."
  value       = var.preserve_host ? opnsense_caddy_header.preserve_host[0].id : ""
}

output "header_ids" {
  description = "Caddy header-operation UUIDs attached to the managed handler."
  value       = local.effective_header_ids
}
