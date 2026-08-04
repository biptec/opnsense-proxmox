variable "interface" {
  description = "Logical OPNsense ingress interface. The default is wan."
  type        = string
  default     = "wan"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.interface))
    error_message = "interface must be a lowercase OPNsense logical identifier such as wan or opt1."
  }
}

variable "destination" {
  description = "Optional destination address or alias matched before translation. Null uses <interface>ip."
  type        = string
  default     = null

  validation {
    condition     = var.destination == null || trimspace(var.destination) != ""
    error_message = "destination must be null or a non-empty address or alias."
  }
}

variable "source_network" {
  description = "Source address, CIDR, or alias allowed to reach the ingress rules."
  type        = string
  default     = "any"

  validation {
    condition     = trimspace(var.source_network) != ""
    error_message = "source_network must not be empty."
  }
}

variable "enabled" {
  description = "Whether all NAT and filter rules are enabled."
  type        = bool
  default     = true
}

variable "external_http_port" {
  description = "HTTP port exposed on the ingress interface."
  type        = number
  default     = 80

  validation {
    condition     = var.external_http_port == floor(var.external_http_port) && var.external_http_port >= 1 && var.external_http_port <= 65535
    error_message = "external_http_port must be an integer between 1 and 65535."
  }
}

variable "external_https_port" {
  description = "HTTPS port exposed on the ingress interface."
  type        = number
  default     = 443

  validation {
    condition     = var.external_https_port == floor(var.external_https_port) && var.external_https_port >= 1 && var.external_https_port <= 65535
    error_message = "external_https_port must be an integer between 1 and 65535."
  }
}

variable "caddy_http_port" {
  description = "Local HTTP port on which Caddy listens. It must not be 80 or 443."
  type        = number
  default     = 8080

  validation {
    condition     = var.caddy_http_port == floor(var.caddy_http_port) && var.caddy_http_port >= 1 && var.caddy_http_port <= 65535
    error_message = "caddy_http_port must be an integer between 1 and 65535."
  }
}

variable "caddy_https_port" {
  description = "Local HTTPS port on which Caddy listens. It must not be 80 or 443."
  type        = number
  default     = 8443

  validation {
    condition     = var.caddy_https_port == floor(var.caddy_https_port) && var.caddy_https_port >= 1 && var.caddy_https_port <= 65535
    error_message = "caddy_https_port must be an integer between 1 and 65535."
  }
}

variable "sequence_base" {
  description = "Sequence used by HTTP rules. HTTPS rules use sequence_base + 1."
  type        = number
  default     = 100

  validation {
    condition     = var.sequence_base == floor(var.sequence_base) && var.sequence_base >= 1 && var.sequence_base <= 2147483646
    error_message = "sequence_base must be an integer between 1 and 2147483646."
  }
}

variable "nat_reflection" {
  description = "NAT reflection mode: default, enable, or disable."
  type        = string
  default     = "disable"

  validation {
    condition     = contains(["default", "enable", "disable"], var.nat_reflection)
    error_message = "nat_reflection must be default, enable, or disable."
  }
}

variable "log_nat" {
  description = "Whether translated packets are logged by the NAT rules."
  type        = bool
  default     = false
}

variable "log_filter" {
  description = "Whether packets accepted by the filter rules are logged."
  type        = bool
  default     = false
}

variable "no_xmlrpc_sync" {
  description = "Exclude generated filter rules from OPNsense HA XMLRPC synchronization."
  type        = bool
  default     = false
}

variable "description_prefix" {
  description = "Prefix used for generated OPNsense rule descriptions."
  type        = string
  default     = "Caddy ingress"

  validation {
    condition = (
      length(var.description_prefix) <= 220 &&
      can(regex("^[A-Za-z0-9 .]+$", var.description_prefix))
    )
    error_message = "description_prefix must contain 1 to 220 ASCII letters, numbers, spaces, or periods."
  }
}
