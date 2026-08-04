variable "import_caddy_settings" {
  description = "Import the existing Caddy settings singleton. Keep true for deployment; mock-provider tests set it to false because OpenTofu testing does not support import."
  type        = bool
  default     = true
}

variable "management_interface" {
  description = "Logical interface reserved for OPNsense management and WebUI access."
  type        = string
  default     = "lan"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*$", var.management_interface))
    error_message = "management_interface must be a lowercase OPNsense interface identifier."
  }
}

variable "public_ingress_interface" {
  description = "Logical interface receiving public HTTP and HTTPS traffic."
  type        = string
  default     = "wan"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*$", var.public_ingress_interface))
    error_message = "public_ingress_interface must be a lowercase OPNsense interface identifier."
  }
}

variable "public_destination" {
  description = "Optional public address or alias. Null uses <public_ingress_interface>ip."
  type        = string
  default     = null

  validation {
    condition     = var.public_destination == null || trimspace(var.public_destination) != ""
    error_message = "public_destination must be null or non-empty."
  }
}

variable "public_source_network" {
  description = "Source address, CIDR, or alias allowed to use public ingress."
  type        = string
  default     = "any"
}

variable "internal_ingress_interface" {
  description = "Logical service interface receiving split-DNS HTTP and HTTPS traffic."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*$", var.internal_ingress_interface))
    error_message = "internal_ingress_interface must be a lowercase OPNsense interface identifier."
  }
}

variable "internal_service_address" {
  description = "Dedicated IPv4 service address used by internal DNAT and Unbound. It must not be the management address."
  type        = string

  validation {
    condition = (
      !strcontains(var.internal_service_address, "/") &&
      can(cidrnetmask("${var.internal_service_address}/32"))
    )
    error_message = "internal_service_address must be one IPv4 address without a prefix."
  }
}

variable "internal_source_network" {
  description = "Source address, CIDR, or alias allowed to use internal ingress."
  type        = string
  default     = "any"
}

variable "caddy_http_port" {
  description = "Local Caddy HTTP listener."
  type        = number
  default     = 8080
}

variable "caddy_https_port" {
  description = "Local Caddy HTTPS listener."
  type        = number
  default     = 8443
}

variable "acme_email" {
  description = "Email address used by public ACME issuance."
  type        = string
  default     = ""
}

variable "public_sequence_base" {
  description = "Sequence used by public HTTP rules; HTTPS uses the next value."
  type        = number
  default     = 100
}

variable "internal_sequence_base" {
  description = "Sequence used by internal HTTP rules; HTTPS uses the next value."
  type        = number
  default     = 200
}

variable "public_domain" {
  description = "Public FQDN whose external DNS is managed outside this configuration."
  type        = string

  validation {
    condition = (
      length(trimsuffix(var.public_domain, ".")) <= 253 &&
      length(split(".", trimsuffix(var.public_domain, "."))) >= 2 &&
      alltrue([
        for label in split(".", trimsuffix(var.public_domain, ".")) :
        length(label) >= 1 && length(label) <= 63 &&
        can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", label))
      ])
    )
    error_message = "public_domain must be a non-wildcard FQDN with valid DNS labels."
  }
}

variable "public_upstream_domains" {
  description = "Addresses or names receiving traffic for the public domain."
  type        = set(string)

  validation {
    condition     = length(var.public_upstream_domains) > 0
    error_message = "public_upstream_domains must not be empty."
  }
}

variable "public_upstream_port" {
  description = "TCP port used by public upstreams."
  type        = number

  validation {
    condition     = var.public_upstream_port == floor(var.public_upstream_port) && var.public_upstream_port >= 1 && var.public_upstream_port <= 65535
    error_message = "public_upstream_port must be an integer between 1 and 65535."
  }
}

variable "public_upstream_protocol" {
  description = "Protocol used by public upstreams."
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "https", "h2c"], var.public_upstream_protocol)
    error_message = "public_upstream_protocol must be http, https, or h2c."
  }
}

variable "internal_domain" {
  description = "Internal FQDN created in Unbound and served with an OPNsense-issued certificate."
  type        = string

  validation {
    condition = (
      length(trimsuffix(var.internal_domain, ".")) <= 253 &&
      length(split(".", trimsuffix(var.internal_domain, "."))) >= 2 &&
      alltrue([
        for label in split(".", trimsuffix(var.internal_domain, ".")) :
        length(label) >= 1 && length(label) <= 63 &&
        can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", label))
      ])
    )
    error_message = "internal_domain must be a non-wildcard FQDN with valid DNS labels."
  }
}

variable "internal_upstream_domains" {
  description = "Addresses or names receiving traffic for the internal domain."
  type        = set(string)

  validation {
    condition     = length(var.internal_upstream_domains) > 0
    error_message = "internal_upstream_domains must not be empty."
  }
}

variable "internal_upstream_port" {
  description = "TCP port used by internal upstreams."
  type        = number

  validation {
    condition     = var.internal_upstream_port == floor(var.internal_upstream_port) && var.internal_upstream_port >= 1 && var.internal_upstream_port <= 65535
    error_message = "internal_upstream_port must be an integer between 1 and 65535."
  }
}

variable "internal_upstream_protocol" {
  description = "Protocol used by internal upstreams."
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "https", "h2c"], var.internal_upstream_protocol)
    error_message = "internal_upstream_protocol must be http, https, or h2c."
  }
}

variable "internal_ca_name" {
  description = "Exact existing OPNsense CA name, common name, description, or reference ID."
  type        = string

  validation {
    condition     = trimspace(var.internal_ca_name) != ""
    error_message = "internal_ca_name must not be empty."
  }
}

variable "internal_certificate_lifetime_days" {
  description = "Validity of the dynamically issued internal certificate."
  type        = number
  default     = 3650

  validation {
    condition     = var.internal_certificate_lifetime_days >= 1
    error_message = "internal_certificate_lifetime_days must be at least 1."
  }
}

variable "internal_allowed_networks" {
  description = "Optional Caddy access-list networks for the internal domain."
  type        = set(string)
  default     = []
}

variable "internal_upstream_tls_ca_ref_id" {
  description = "Optional OPNsense CA reference trusted for an HTTPS internal upstream."
  type        = string
  default     = null
}

variable "internal_upstream_tls_server_name" {
  description = "Optional TLS server name used for an HTTPS internal upstream."
  type        = string
  default     = null
}
