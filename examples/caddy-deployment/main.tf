provider "opnsense" {}

locals {
  internal_labels   = split(".", trimsuffix(lower(var.internal_domain), "."))
  internal_hostname = local.internal_labels[0]
  internal_zone     = join(".", slice(local.internal_labels, 1, length(local.internal_labels)))
}

import {
  for_each = var.import_caddy_settings ? toset(["caddy_settings"]) : toset([])

  to = opnsense_caddy_settings.main
  id = each.value
}

resource "opnsense_caddy_settings" "main" {
  enabled          = true
  http_port        = var.caddy_http_port
  https_port       = var.caddy_https_port
  acme_email       = var.acme_email
  run_as_user      = "root"
  http_versions    = ["h1", "h2"]
  listen_addresses = [var.public_destination, var.internal_service_address]

  lifecycle {
    precondition {
      condition     = var.public_ingress_interface != var.management_interface
      error_message = "public_ingress_interface must be different from management_interface."
    }

    precondition {
      condition     = var.internal_ingress_interface != var.management_interface
      error_message = "internal_ingress_interface must be different from management_interface."
    }

    precondition {
      condition     = var.public_ingress_interface != var.internal_ingress_interface
      error_message = "public and internal ingress must use different logical interfaces."
    }

    precondition {
      condition     = var.public_destination != var.internal_service_address
      error_message = "public and internal Caddy listener addresses must be different."
    }

    precondition {
      condition     = lower(trimsuffix(var.public_domain, ".")) != lower(trimsuffix(var.internal_domain, "."))
      error_message = "public_domain and internal_domain must be different."
    }
  }
}

module "public_ingress" {
  source = "../../modules/caddy-edge-ingress"

  interface          = var.public_ingress_interface
  destination        = var.public_destination
  source_network     = var.public_source_network
  caddy_http_port    = var.caddy_http_port
  caddy_https_port   = var.caddy_https_port
  sequence_base      = var.public_sequence_base
  nat_reflection     = "disable"
  description_prefix = "Caddy public ingress"

  depends_on = [opnsense_caddy_settings.main]
}

module "internal_ingress" {
  source = "../../modules/caddy-edge-ingress"

  interface          = var.internal_ingress_interface
  destination        = var.internal_service_address
  source_network     = var.internal_source_network
  caddy_http_port    = var.caddy_http_port
  caddy_https_port   = var.caddy_https_port
  sequence_base      = var.internal_sequence_base
  nat_reflection     = "disable"
  description_prefix = "Caddy internal ingress"

  depends_on = [opnsense_caddy_settings.main]
}

module "public_proxy" {
  source = "../../modules/caddy-reverse-proxy"

  domain            = trimsuffix(lower(var.public_domain), ".")
  upstream_domains  = var.public_upstream_domains
  upstream_port     = var.public_upstream_port
  upstream_protocol = var.public_upstream_protocol
  certificate_mode  = "acme"
  description       = "Public reverse proxy"

  depends_on = [module.public_ingress]
}

module "internal_proxy" {
  source = "../../modules/caddy-reverse-proxy"

  domain                             = trimsuffix(lower(var.internal_domain), ".")
  upstream_domains                   = var.internal_upstream_domains
  upstream_port                      = var.internal_upstream_port
  upstream_protocol                  = var.internal_upstream_protocol
  certificate_mode                   = "internal"
  internal_ca_name                   = var.internal_ca_name
  internal_certificate_lifetime_days = var.internal_certificate_lifetime_days
  allowed_networks                   = var.internal_allowed_networks
  upstream_tls_ca_ref_id             = var.internal_upstream_tls_ca_ref_id
  upstream_tls_server_name           = var.internal_upstream_tls_server_name
  description                        = "Internal reverse proxy"

  depends_on = [module.internal_ingress]
}

resource "opnsense_unbound_host_override" "internal_proxy" {
  enabled     = true
  type        = "A"
  hostname    = local.internal_hostname
  domain      = local.internal_zone
  server      = var.internal_service_address
  description = "Internal Caddy service"

  depends_on = [module.internal_proxy]
}
