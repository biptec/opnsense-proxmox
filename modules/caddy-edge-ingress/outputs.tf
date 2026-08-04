output "http_filter_id" {
  description = "UUID of the HTTP pass rule."
  value       = opnsense_firewall_filter.http.id
}

output "https_filter_id" {
  description = "UUID of the HTTPS pass rule."
  value       = opnsense_firewall_filter.https.id
}

output "destination" {
  description = "Effective destination address or alias matched by both rules."
  value       = local.destination_net
}
