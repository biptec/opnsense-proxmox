output "caddy_http_port" {
  description = "Global Caddy HTTP listener port."
  value       = opnsense_caddy_settings.main.http_port
}

output "caddy_https_port" {
  description = "Global Caddy HTTPS listener port."
  value       = opnsense_caddy_settings.main.https_port
}

output "ingress_destination" {
  description = "Effective destination matched by the global ingress rules."
  value       = module.edge_ingress.destination
}

output "http_filter_id" {
  description = "UUID of the global HTTP pass rule."
  value       = module.edge_ingress.http_filter_id
}

output "https_filter_id" {
  description = "UUID of the global HTTPS pass rule."
  value       = module.edge_ingress.https_filter_id
}
