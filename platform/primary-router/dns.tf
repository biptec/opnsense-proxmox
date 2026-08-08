locals {
  dns_primary_ns_fqdn = "${var.dns_zone.primary_ns_label}.${var.dns_zone.name}"
  internal_dns_ipv4   = module.router_foundation.service_addresses["dns"]
  internal_dns_ipv6   = try(module.router_foundation.service_ipv6_addresses["dns"], null)
  internal_proxy_ipv4 = module.router_foundation.service_addresses["proxy"]
  internal_proxy_ipv6 = try(module.router_foundation.service_ipv6_addresses["proxy"], null)
  internal_ntp_ipv4   = module.router_foundation.service_addresses["ntp"]
  internal_ntp_ipv6   = try(module.router_foundation.service_ipv6_addresses["ntp"], null)
}

resource "opnsense_bind_acl" "internal_clients" {
  name     = "platform_internal_clients"
  networks = var.trusted_internal_networks

  depends_on = [module.router_services]
}

resource "opnsense_bind_acl" "internal_dns_destination" {
  name = "platform_internal_dns_dst"
  networks = toset(concat(
    ["${local.internal_dns_ipv4}/32"],
    local.internal_dns_ipv6 == null ? [] : ["${local.internal_dns_ipv6}/128"],
  ))

  depends_on = [module.router_services]
}

resource "opnsense_bind_acl" "public_dns_destination" {
  name = "platform_public_dns_destination"
  networks = [
    "${var.wan.public_dns_address}/32",
    "${var.wan.public_dns_ipv6_address}/128",
  ]

  depends_on = [module.router_services]
}

resource "opnsense_bind_view" "internal" {
  sequence                  = 10
  name                      = "internal"
  match_client_acl_ids      = [opnsense_bind_acl.internal_clients.id]
  match_destination_acl_ids = [opnsense_bind_acl.internal_dns_destination.id]
  recursion                 = true
  allow_recursion_acl_ids   = [opnsense_bind_acl.internal_clients.id]
  allow_query_acl_ids       = [opnsense_bind_acl.internal_clients.id]
  dnssec_validation         = "auto"
}

resource "opnsense_bind_view" "public" {
  sequence                  = 100
  name                      = "public"
  match_any                 = true
  match_destination_acl_ids = [opnsense_bind_acl.public_dns_destination.id]
  allow_query_any           = true
  recursion                 = false
  dnssec_validation         = "auto"
}

resource "opnsense_bind_primary_domain" "internal" {
  view_id         = opnsense_bind_view.internal.id
  domain_name     = var.dns_zone.name
  dns_server      = local.dns_primary_ns_fqdn
  mail_admin      = var.dns_zone.soa_mail_admin
  dnssec          = var.dns_zone.dnssec
  ttl             = var.dns_zone.ttl
  refresh         = var.dns_zone.refresh
  retry           = var.dns_zone.retry
  expire          = var.dns_zone.expire
  negative_ttl    = var.dns_zone.negative_ttl
  transfer_key_id = ""
  also_notify     = []

  lifecycle {
    ignore_changes = [transfer_key_id, also_notify]
  }
}

resource "opnsense_bind_primary_domain" "public" {
  view_id         = opnsense_bind_view.public.id
  domain_name     = var.dns_zone.name
  dns_server      = local.dns_primary_ns_fqdn
  mail_admin      = var.dns_zone.soa_mail_admin
  dnssec          = var.dns_zone.dnssec
  ttl             = var.dns_zone.ttl
  refresh         = var.dns_zone.refresh
  retry           = var.dns_zone.retry
  expire          = var.dns_zone.expire
  negative_ttl    = var.dns_zone.negative_ttl
  transfer_key_id = ""
  also_notify     = []

  lifecycle {
    ignore_changes = [transfer_key_id, also_notify]
  }
}

resource "opnsense_bind_record" "internal_ns" {
  domain_id = opnsense_bind_primary_domain.internal.id
  name      = "@"
  type      = "NS"
  value     = "${local.dns_primary_ns_fqdn}."
}

resource "opnsense_bind_record" "internal_ns_ipv4" {
  domain_id = opnsense_bind_primary_domain.internal.id
  name      = var.dns_zone.primary_ns_label
  type      = "A"
  value     = local.internal_dns_ipv4
}

resource "opnsense_bind_record" "internal_ns_ipv6" {
  count = local.internal_dns_ipv6 == null ? 0 : 1

  domain_id = opnsense_bind_primary_domain.internal.id
  name      = var.dns_zone.primary_ns_label
  type      = "AAAA"
  value     = local.internal_dns_ipv6
}

resource "opnsense_bind_record" "internal_proxy_ipv4" {
  domain_id = opnsense_bind_primary_domain.internal.id
  name      = "proxy"
  type      = "A"
  value     = local.internal_proxy_ipv4
}

resource "opnsense_bind_record" "internal_proxy_ipv6" {
  count = local.internal_proxy_ipv6 == null ? 0 : 1

  domain_id = opnsense_bind_primary_domain.internal.id
  name      = "proxy"
  type      = "AAAA"
  value     = local.internal_proxy_ipv6
}

resource "opnsense_bind_record" "internal_ntp1_ipv4" {
  domain_id = opnsense_bind_primary_domain.internal.id
  name      = "ntp1"
  type      = "A"
  value     = local.internal_ntp_ipv4
}

resource "opnsense_bind_record" "internal_ntp1_ipv6" {
  count = local.internal_ntp_ipv6 == null ? 0 : 1

  domain_id = opnsense_bind_primary_domain.internal.id
  name      = "ntp1"
  type      = "AAAA"
  value     = local.internal_ntp_ipv6
}

resource "opnsense_bind_record" "public_ns" {
  domain_id = opnsense_bind_primary_domain.public.id
  name      = "@"
  type      = "NS"
  value     = "${local.dns_primary_ns_fqdn}."
}

resource "opnsense_bind_record" "public_ns_ipv4" {
  domain_id = opnsense_bind_primary_domain.public.id
  name      = var.dns_zone.primary_ns_label
  type      = "A"
  value     = var.wan.public_dns_address
}

resource "opnsense_bind_record" "public_ns_ipv6" {
  domain_id = opnsense_bind_primary_domain.public.id
  name      = var.dns_zone.primary_ns_label
  type      = "AAAA"
  value     = var.wan.public_dns_ipv6_address
}

resource "opnsense_bind_record" "public_proxy_ipv4" {
  domain_id = opnsense_bind_primary_domain.public.id
  name      = "proxy"
  type      = "A"
  value     = var.wan.public_proxy_address
  enabled   = var.cutover.public_proxy_vip
}

resource "opnsense_bind_record" "public_proxy_ipv6" {
  domain_id = opnsense_bind_primary_domain.public.id
  name      = "proxy"
  type      = "AAAA"
  value     = var.wan.public_proxy_ipv6_address
  enabled   = var.cutover.public_proxy_vip
}

resource "opnsense_dns_service_cutover" "primary" {
  target                 = var.cutover.dns_target
  allow_cutover          = var.cutover.allow_dns_cutover
  verify_timeout_seconds = var.cutover.dns_verify_timeout

  depends_on = [
    module.router_services,
    opnsense_bind_record.internal_ns,
    opnsense_bind_record.internal_ns_ipv4,
    opnsense_bind_record.internal_ns_ipv6,
    opnsense_bind_record.internal_proxy_ipv4,
    opnsense_bind_record.internal_proxy_ipv6,
    opnsense_bind_record.internal_ntp1_ipv4,
    opnsense_bind_record.internal_ntp1_ipv6,
    opnsense_bind_record.public_ns,
    opnsense_bind_record.public_ns_ipv4,
    opnsense_bind_record.public_ns_ipv6,
    opnsense_bind_record.public_proxy_ipv4,
    opnsense_bind_record.public_proxy_ipv6,
  ]
}
