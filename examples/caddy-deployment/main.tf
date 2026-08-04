provider "opnsense" {}

locals {
  normalized_routes = {
    for domain, route in var.routes :
    trimsuffix(lower(domain), ".") => route
  }

  unbound_routes = {
    for domain, route in local.normalized_routes :
    domain => route if route.unbound_address != null
  }

  dns_parts = {
    for domain in keys(local.unbound_routes) :
    domain => split(".", domain)
  }
}

module "route" {
  for_each = local.normalized_routes
  source   = "../../modules/caddy-reverse-proxy"

  domain            = each.key
  upstream_domains  = each.value.upstream_domains
  upstream_port     = each.value.upstream_port
  upstream_protocol = each.value.upstream_protocol
  certificate_mode  = each.value.certificate_mode

  internal_ca_name                   = each.value.internal_ca_name
  internal_certificate_lifetime_days = each.value.internal_certificate_lifetime_days
  certificate_ref_id                 = each.value.certificate_ref_id
  allowed_networks                   = each.value.allowed_networks
  access_list_name                   = each.value.access_list_name
  upstream_tls_ca_ref_id             = each.value.upstream_tls_ca_ref_id
  upstream_tls_server_name           = each.value.upstream_tls_server_name
  load_balancing_policy              = each.value.load_balancing_policy
  health_uri                         = each.value.health_uri
  health_status                      = each.value.health_status
  description                        = coalesce(each.value.description, "Reverse proxy for ${each.key}")
}

resource "opnsense_unbound_host_override" "route" {
  for_each = local.unbound_routes

  enabled  = true
  type     = "A"
  hostname = local.dns_parts[each.key][0]
  domain = join(
    ".",
    slice(local.dns_parts[each.key], 1, length(local.dns_parts[each.key])),
  )
  server      = each.value.unbound_address
  description = coalesce(each.value.description, "DNS for ${each.key}")

  depends_on = [module.route]
}
