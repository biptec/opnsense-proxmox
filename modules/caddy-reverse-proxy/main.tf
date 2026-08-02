locals {
  creates_access_list = length(var.allowed_networks) > 0
  generated_access_list_name = coalesce(
    var.access_list_name,
    replace(replace(var.domain, "*.", "wildcard-"), ".", "-")
  )
  effective_access_list_id = local.creates_access_list ? opnsense_caddy_access_list.this[0].id : (var.access_list_id != null ? var.access_list_id : "")
}

resource "opnsense_caddy_access_list" "this" {
  count = local.creates_access_list ? 1 : 0

  name        = local.generated_access_list_name
  client_ips  = var.allowed_networks
  description = var.description
}

resource "opnsense_caddy_domain" "this" {
  domain           = var.domain
  protocol         = var.frontend_protocol
  certificate_mode = var.certificate_mode

  internal_ca_name                   = var.certificate_mode == "internal" ? var.internal_ca_name : null
  internal_certificate_lifetime_days = var.internal_certificate_lifetime_days
  certificate_ref_id                 = var.certificate_mode == "custom" ? var.certificate_ref_id : null
  access_list_id                     = local.effective_access_list_id
  description                        = var.description

  lifecycle {
    precondition {
      condition     = !(local.creates_access_list && var.access_list_id != null)
      error_message = "allowed_networks and access_list_id cannot be used together."
    }

    precondition {
      condition     = var.certificate_mode != "internal" || var.internal_ca_name != null
      error_message = "internal_ca_name is required when certificate_mode is internal."
    }

    precondition {
      condition     = var.certificate_mode != "custom" || var.certificate_ref_id != null
      error_message = "certificate_ref_id is required when certificate_mode is custom."
    }

    precondition {
      condition = (
        (var.frontend_protocol == "http" && var.certificate_mode == "none") ||
        (var.frontend_protocol == "https" && var.certificate_mode != "none")
      )
      error_message = "HTTP requires certificate_mode none; HTTPS requires acme, internal, or custom."
    }
  }
}

resource "opnsense_caddy_handler" "this" {
  domain_id         = opnsense_caddy_domain.this.id
  upstream_domains  = var.upstream_domains
  upstream_port     = var.upstream_port
  upstream_protocol = var.upstream_protocol

  tls_trust_ca_ref_id   = var.upstream_protocol == "https" ? var.upstream_tls_ca_ref_id != null ? var.upstream_tls_ca_ref_id : "" : ""
  tls_server_name       = var.upstream_protocol == "https" ? var.upstream_tls_server_name != null ? var.upstream_tls_server_name : "" : ""
  load_balancing_policy = var.load_balancing_policy != null ? var.load_balancing_policy : ""
  health_uri            = var.health_uri != null ? var.health_uri : ""
  health_status         = var.health_status != null ? var.health_status : ""
  description           = var.description
}
