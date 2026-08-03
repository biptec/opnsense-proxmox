variable "domain" {
  description = "Frontend FQDN handled by Caddy. Public DNS is managed outside this module."
  type        = string

  validation {
    condition     = trimspace(var.domain) != ""
    error_message = "domain must not be empty."
  }
}

variable "upstream_domains" {
  description = "Internal IP addresses, hostnames, or FQDNs receiving proxied traffic."
  type        = set(string)

  validation {
    condition     = length(var.upstream_domains) > 0
    error_message = "upstream_domains must contain at least one address."
  }
}

variable "upstream_port" {
  description = "TCP port used by every upstream in upstream_domains."
  type        = number

  validation {
    condition     = var.upstream_port >= 1 && var.upstream_port <= 65535
    error_message = "upstream_port must be between 1 and 65535."
  }
}

variable "upstream_protocol" {
  description = "Upstream protocol: http, https, or h2c."
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "https", "h2c"], var.upstream_protocol)
    error_message = "upstream_protocol must be http, https, or h2c."
  }
}

variable "frontend_protocol" {
  description = "Frontend protocol exposed by Caddy: https or http."
  type        = string
  default     = "https"

  validation {
    condition     = contains(["https", "http"], var.frontend_protocol)
    error_message = "frontend_protocol must be https or http."
  }
}

variable "certificate_mode" {
  description = "Certificate mode: acme, internal, custom, or none."
  type        = string
  default     = "acme"

  validation {
    condition     = contains(["acme", "internal", "custom", "none"], var.certificate_mode)
    error_message = "certificate_mode must be acme, internal, custom, or none."
  }
}

variable "internal_ca_name" {
  description = "Exact existing OPNsense CA name, common name, description, or reference ID used for internal certificates."
  type        = string
  default     = null
}

variable "internal_certificate_lifetime_days" {
  description = "Validity of dynamically issued internal certificates in days."
  type        = number
  default     = 3650

  validation {
    condition     = var.internal_certificate_lifetime_days >= 1
    error_message = "internal_certificate_lifetime_days must be at least 1."
  }
}

variable "certificate_ref_id" {
  description = "Existing OPNsense certificate reference ID used when certificate_mode is custom."
  type        = string
  default     = null
}

variable "allowed_networks" {
  description = "Optional client IP networks allowed to access the domain. When non-empty, the module creates a Caddy access list."
  type        = set(string)
  default     = []
}

variable "access_list_id" {
  description = "Optional existing Caddy access-list UUID. It cannot be combined with allowed_networks."
  type        = string
  default     = null
}

variable "access_list_name" {
  description = "Optional name for the access list created from allowed_networks. The domain-derived name is used when null."
  type        = string
  default     = null
}

variable "upstream_tls_ca_ref_id" {
  description = "Optional OPNsense CA reference ID trusted for an HTTPS upstream."
  type        = string
  default     = null
}

variable "upstream_tls_server_name" {
  description = "Optional TLS server name used to verify an HTTPS upstream certificate."
  type        = string
  default     = null
}

variable "load_balancing_policy" {
  description = "Optional Caddy load-balancing policy: first, round_robin, least_conn, ip_hash, client_ip_hash, or uri_hash."
  type        = string
  default     = null

  validation {
    condition = var.load_balancing_policy == null || contains([
      "first",
      "round_robin",
      "least_conn",
      "ip_hash",
      "client_ip_hash",
      "uri_hash",
    ], var.load_balancing_policy)
    error_message = "load_balancing_policy must be null, first, round_robin, least_conn, ip_hash, client_ip_hash, or uri_hash."
  }
}

variable "health_uri" {
  description = "Optional active health-check URI beginning with a slash."
  type        = string
  default     = null

  validation {
    condition     = var.health_uri == null || startswith(var.health_uri, "/")
    error_message = "health_uri must be null or begin with a slash."
  }
}

variable "health_status" {
  description = "Optional expected health-check status such as 200 or 2xx."
  type        = string
  default     = null

  validation {
    condition = (
      var.health_status == null ||
      can(regex("^[1-5](?:[0-9]{2}|xx)$", lower(var.health_status)))
    )
    error_message = "health_status must be null, a three-digit HTTP status from 100 to 599, or a class such as 2xx."
  }
}

variable "description" {
  description = "Optional description applied to the Caddy domain, handler, and generated access list."
  type        = string
  default     = ""
}
