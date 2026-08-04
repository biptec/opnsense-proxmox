variable "routes" {
  description = "Application-owned Caddy routes keyed by frontend FQDN."

  type = map(object({
    upstream_domains                   = set(string)
    upstream_port                      = number
    upstream_protocol                  = optional(string, "http")
    certificate_mode                   = optional(string, "acme")
    internal_ca_name                   = optional(string)
    internal_certificate_lifetime_days = optional(number, 3650)
    certificate_ref_id                 = optional(string)
    allowed_networks                   = optional(set(string), [])
    access_list_name                   = optional(string)
    upstream_tls_ca_ref_id             = optional(string)
    upstream_tls_server_name           = optional(string)
    load_balancing_policy              = optional(string)
    health_uri                         = optional(string)
    health_status                      = optional(string)
    unbound_address                    = optional(string)
    description                        = optional(string)
  }))

  validation {
    condition     = length(var.routes) > 0
    error_message = "routes must contain at least one application domain."
  }

  validation {
    condition = alltrue([
      for domain in keys(var.routes) :
      length(trimsuffix(domain, ".")) <= 253 &&
      length(split(".", trimsuffix(domain, "."))) >= 2 &&
      alltrue([
        for label in split(".", trimsuffix(domain, ".")) :
        length(label) >= 1 && length(label) <= 63 &&
        can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", label))
      ])
    ])
    error_message = "Every route key must be a valid non-wildcard FQDN."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      length(route.upstream_domains) > 0 &&
      route.upstream_port == floor(route.upstream_port) &&
      route.upstream_port >= 1 && route.upstream_port <= 65535
    ])
    error_message = "Every route requires an upstream and a valid TCP port."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      contains(["http", "https", "h2c"], route.upstream_protocol)
    ])
    error_message = "upstream_protocol must be http, https, or h2c."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      contains(["acme", "internal", "custom"], route.certificate_mode)
    ])
    error_message = "certificate_mode must be acme, internal, or custom."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      route.certificate_mode != "internal" ||
      (route.internal_ca_name != null && trimspace(route.internal_ca_name) != "")
    ])
    error_message = "internal certificate mode requires internal_ca_name."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      route.certificate_mode != "custom" ||
      (route.certificate_ref_id != null && trimspace(route.certificate_ref_id) != "")
    ])
    error_message = "custom certificate mode requires certificate_ref_id."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      route.unbound_address == null || (
        !strcontains(route.unbound_address, "/") &&
        can(cidrnetmask("${route.unbound_address}/32"))
      )
    ])
    error_message = "unbound_address must be null or one IPv4 address without a prefix."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      route.internal_certificate_lifetime_days >= 1
    ])
    error_message = "internal certificate lifetime must be at least one day."
  }
}
