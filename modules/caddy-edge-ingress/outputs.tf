output "http_nat_id" {
  description = "UUID of the HTTP destination NAT rule."
  value       = opnsense_firewall_nat_port_forward.http.id
}

output "https_nat_id" {
  description = "UUID of the HTTPS destination NAT rule."
  value       = opnsense_firewall_nat_port_forward.https.id
}

output "http_filter_id" {
  description = "UUID of the HTTP pass rule."
  value       = opnsense_firewall_filter.http.id
}

output "https_filter_id" {
  description = "UUID of the HTTPS pass rule."
  value       = opnsense_firewall_filter.https.id
}

output "destination" {
  description = "Effective destination address or alias matched before translation."
  value       = local.destination_net
}
