variable "wan_interface" {
  description = "Existing logical WAN interface that owns the public service VIPs."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.wan_interface))
    error_message = "wan_interface must be a lowercase OPNsense logical interface identifier."
  }
}

variable "management_address" {
  description = "Management IPv4 address that must not be reused by a service listener."
  type        = string

  validation {
    condition = (
      !strcontains(var.management_address, "/") &&
      can(cidrnetmask("${var.management_address}/32")) &&
      var.management_address != "0.0.0.0" &&
      !startswith(var.management_address, "127.")
    )
    error_message = "management_address must be a non-wildcard IPv4 address without a prefix."
  }
}

variable "wan_primary_address" {
  description = "Primary WAN IPv4 address that must not be reused by a service VIP."
  type        = string

  validation {
    condition = (
      !strcontains(var.wan_primary_address, "/") &&
      can(cidrnetmask("${var.wan_primary_address}/32")) &&
      var.wan_primary_address != "0.0.0.0" &&
      !startswith(var.wan_primary_address, "127.")
    )
    error_message = "wan_primary_address must be a non-wildcard IPv4 address without a prefix."
  }
}

variable "api_extensions_plugin_id" {
  description = "Dependency token exported by the router-foundation module."
  type        = string

  validation {
    condition     = trimspace(var.api_extensions_plugin_id) != ""
    error_message = "api_extensions_plugin_id must come from the router-foundation module."
  }
}

variable "public_dns_address" {
  description = "Dedicated public IPv4 address for authoritative DNS."
  type        = string

  validation {
    condition = (
      !strcontains(var.public_dns_address, "/") &&
      can(cidrnetmask("${var.public_dns_address}/32")) &&
      var.public_dns_address != "0.0.0.0" &&
      !startswith(var.public_dns_address, "127.")
    )
    error_message = "public_dns_address must be a non-wildcard IPv4 address without a prefix."
  }
}

variable "public_dns_vip_enabled" {
  description = "Attach the public DNS IP Alias to WAN. Keep false until the guarded DNS cutover and ingress policy are ready."
  type        = bool
  default     = false
}

variable "public_caddy_address" {
  description = "Dedicated public IPv4 address for Caddy HTTP and HTTPS ingress."
  type        = string

  validation {
    condition = (
      !strcontains(var.public_caddy_address, "/") &&
      can(cidrnetmask("${var.public_caddy_address}/32")) &&
      var.public_caddy_address != "0.0.0.0" &&
      !startswith(var.public_caddy_address, "127.")
    )
    error_message = "public_caddy_address must be a non-wildcard IPv4 address without a prefix."
  }
}

variable "public_caddy_vip_enabled" {
  description = "Attach the public Caddy IP Alias to WAN. Keep false until Caddy configuration and ingress policy are ready."
  type        = bool
  default     = false
}

variable "service_addresses" {
  description = "Service endpoint addresses produced by the router-foundation module. Required keys are dns, ntp, and caddy."
  type        = map(string)

  validation {
    condition = (
      alltrue([for name in ["dns", "ntp", "caddy"] : contains(keys(var.service_addresses), name)]) &&
      length(toset(values(var.service_addresses))) == length(var.service_addresses) &&
      alltrue([
        for address in values(var.service_addresses) :
        !strcontains(address, "/") &&
        can(cidrnetmask("${address}/32")) &&
        address != "0.0.0.0" &&
        !startswith(address, "127.")
      ])
    )
    error_message = "service_addresses must contain unique dns, ntp, and caddy addresses."
  }
}

variable "service_interfaces" {
  description = "Logical service interfaces produced by the router-foundation module. The ntp key is required."
  type        = map(string)

  validation {
    condition = (
      contains(keys(var.service_interfaces), "ntp") &&
      alltrue([
        for name, interface in var.service_interfaces :
        can(regex("^[a-z][a-z0-9_]*$", name)) &&
        can(regex("^[a-z][a-z0-9_]*$", interface))
      ])
    )
    error_message = "service_interfaces must contain ntp and valid logical interface identifiers."
  }
}

variable "bind_enabled" {
  description = "Optional bootstrap override for the BIND service flag. Leave null when the DNS cutover resource owns active-service state."
  type        = bool
  default     = null
  nullable    = true
}

variable "bind_log_level" {
  description = "BIND log level."
  type        = string
  default     = "info"

  validation {
    condition     = contains(["critical", "error", "warning", "notice", "info", "debug", "dynamic"], var.bind_log_level)
    error_message = "bind_log_level must be a value supported by os-bind."
  }
}

variable "bind_rate_limit_count" {
  description = "BIND response-rate limit per second."
  type        = number
  default     = 20

  validation {
    condition     = var.bind_rate_limit_count == floor(var.bind_rate_limit_count) && var.bind_rate_limit_count >= 1
    error_message = "bind_rate_limit_count must be a positive integer."
  }
}

variable "caddy_enabled" {
  description = "Enable Caddy only after at least one proxy domain is managed by a site layer."
  type        = bool
  default     = false
}

variable "caddy_acme_email" {
  description = "Email address used by public ACME issuers. Empty is allowed while Caddy is disabled."
  type        = string
  default     = ""

  validation {
    condition = (
      var.caddy_acme_email == "" ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+$", var.caddy_acme_email))
    )
    error_message = "caddy_acme_email must be empty or a valid email address."
  }
}

variable "caddy_http_versions" {
  description = "Frontend HTTP versions enabled by Caddy."
  type        = set(string)
  default     = ["h1", "h2"]

  validation {
    condition = (
      length(var.caddy_http_versions) > 0 &&
      alltrue([for version in var.caddy_http_versions : contains(["h1", "h2", "h3"], version)])
    )
    error_message = "caddy_http_versions must contain one or more of h1, h2, or h3."
  }
}

variable "ntp_enabled" {
  description = "Enable the built-in NTP service on the dedicated service interface."
  type        = bool
  default     = true
}

variable "ntp_serve_clients" {
  description = "Serve NTP clients on the dedicated service interface. Keep false until ingress policy permits UDP/123 only to the portable .2 service address."
  type        = bool
  default     = false
}

variable "ntp_servers" {
  description = "Upstream NTP servers."
  type = set(object({
    host     = string
    noselect = optional(bool, false)
    prefer   = optional(bool, false)
    iburst   = optional(bool, true)
    pool     = optional(bool, false)
  }))

  validation {
    condition = (
      length(var.ntp_servers) > 0 &&
      alltrue([for server in var.ntp_servers : trimspace(server.host) != ""])
    )
    error_message = "ntp_servers must contain at least one server with a non-empty host."
  }
}
