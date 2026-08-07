locals {
  internal_dns_address   = try(var.service_addresses["dns"], "")
  internal_ntp_address   = try(var.service_addresses["ntp"], "")
  internal_caddy_address = try(var.service_addresses["caddy"], "")

  bind_listener_addresses = [
    var.public_dns_address,
    local.internal_dns_address,
  ]
  caddy_listener_addresses = [
    var.public_caddy_address,
    local.internal_caddy_address,
  ]
  all_listener_addresses = concat(
    local.bind_listener_addresses,
    local.caddy_listener_addresses,
    [local.internal_ntp_address],
  )
}

resource "terraform_data" "listener_contract" {
  input = {
    public_dns               = var.public_dns_address
    public_caddy             = var.public_caddy_address
    service                  = var.service_addresses
    ntp_interface            = try(var.service_interfaces["ntp"], "")
    api_extensions_plugin_id = var.api_extensions_plugin_id
  }

  lifecycle {
    precondition {
      condition     = var.management_address != var.wan_primary_address
      error_message = "The management and primary WAN addresses must be different."
    }

    precondition {
      condition     = cidrcontains("${var.wan_primary_address}/${var.wan_primary_prefix}", var.wan_gateway)
      error_message = "The WAN gateway must be on-link through the primary WAN prefix."
    }

    precondition {
      condition = alltrue([
        cidrcontains("${var.wan_primary_address}/${var.wan_primary_prefix}", var.public_dns_address),
        cidrcontains("${var.wan_primary_address}/${var.wan_primary_prefix}", var.public_caddy_address),
      ])
      error_message = "Public DNS and Caddy /32 aliases must be inside the connected primary WAN subnet."
    }

    precondition {
      condition     = var.bind_enabled != true || var.public_dns_vip_enabled
      error_message = "BIND cannot be enabled while the public DNS VIP is detached. Activate the VIP only as part of the guarded DNS cutover."
    }

    precondition {
      condition     = !var.caddy_enabled || var.public_caddy_vip_enabled
      error_message = "Caddy cannot be enabled while the public Caddy VIP is detached."
    }

    precondition {
      condition     = length(toset(local.all_listener_addresses)) == length(local.all_listener_addresses)
      error_message = "Public and internal DNS, NTP, and Caddy listener addresses must all be distinct."
    }

    precondition {
      condition = alltrue([
        for address in values(var.service_addresses) :
        !contains([var.public_dns_address, var.public_caddy_address], address)
      ])
      error_message = "An internal service address must not reuse a public service address."
    }

    precondition {
      condition = alltrue([
        for address in local.all_listener_addresses :
        !contains([var.management_address, var.wan_primary_address], address)
      ])
      error_message = "A service listener must not reuse the management or primary WAN address."
    }
  }
}

resource "opnsense_plugin" "bind" {
  name                 = "os-bind"
  uninstall_on_destroy = false
}

resource "opnsense_plugin" "caddy" {
  name                 = "os-caddy"
  uninstall_on_destroy = false
}

resource "opnsense_interfaces_vip" "public_dns" {
  count = var.public_dns_vip_enabled ? 1 : 0

  mode        = "ipalias"
  interface   = var.wan_interface
  network     = "${var.public_dns_address}/32"
  no_bind     = false
  no_expand   = false
  description = "Public DNS service address"

  depends_on = [
    terraform_data.listener_contract,
    opnsense_ntp_settings.internal,
  ]
}

resource "opnsense_interfaces_vip" "public_caddy" {
  count = var.public_caddy_vip_enabled ? 1 : 0

  mode        = "ipalias"
  interface   = var.wan_interface
  network     = "${var.public_caddy_address}/32"
  no_bind     = false
  no_expand   = false
  description = "Public Caddy service address"

  depends_on = [
    terraform_data.listener_contract,
    opnsense_ntp_settings.internal,
  ]
}

resource "opnsense_bind_settings" "main" {
  enabled              = var.bind_enabled
  disable_ipv6         = true
  listen_ipv4          = local.bind_listener_addresses
  listen_ipv6          = ["::1"]
  port                 = 53
  hide_hostname        = true
  hide_version         = true
  enable_rate_limiting = true
  rate_limit_count     = var.bind_rate_limit_count
  log_level            = var.bind_log_level

  depends_on = [
    opnsense_plugin.bind,
    opnsense_interfaces_vip.public_dns,
  ]
}

resource "opnsense_ntp_settings" "internal" {
  enabled                = var.ntp_enabled
  servers                = var.ntp_servers
  interfaces             = [try(var.service_interfaces["ntp"], "")]
  client_mode            = false
  kiss_of_death          = true
  rate_limiting          = true
  deny_modifications     = true
  disable_queries        = true
  disable_serving        = !var.ntp_serve_clients
  deny_peer_associations = true
  deny_trap_service      = true

  depends_on = [terraform_data.listener_contract]
}

resource "opnsense_caddy_settings" "main" {
  enabled          = var.caddy_enabled
  enable_layer4    = false
  http_port        = 80
  https_port       = 443
  listen_addresses = local.caddy_listener_addresses
  acme_email       = var.caddy_acme_email
  auto_https       = ""
  run_as_user      = "root"
  http_versions    = var.caddy_http_versions

  depends_on = [
    opnsense_plugin.caddy,
    opnsense_interfaces_vip.public_caddy,
  ]
}
