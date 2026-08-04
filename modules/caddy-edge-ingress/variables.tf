variable "interface" {
  description = "Logical OPNsense ingress interface."
  type        = string
  default     = "wan"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.interface))
    error_message = "interface must be a lowercase OPNsense logical identifier such as wan or opt1."
  }
}

variable "destination" {
  description = "Optional destination address or alias. Null uses <interface>ip."
  type        = string
  default     = null

  validation {
    condition     = var.destination == null || trimspace(var.destination) != ""
    error_message = "destination must be null or a non-empty address or alias."
  }
}

variable "source_network" {
  description = "Source address, CIDR, or alias allowed to reach Caddy."
  type        = string
  default     = "any"

  validation {
    condition     = trimspace(var.source_network) != ""
    error_message = "source_network must not be empty."
  }
}

variable "enabled" {
  description = "Whether the HTTP and HTTPS pass rules are enabled."
  type        = bool
  default     = true
}

variable "http_port" {
  description = "HTTP port on which Caddy listens."
  type        = number
  default     = 80

  validation {
    condition     = var.http_port == floor(var.http_port) && var.http_port >= 1 && var.http_port <= 65535
    error_message = "http_port must be an integer between 1 and 65535."
  }
}

variable "https_port" {
  description = "HTTPS port on which Caddy listens."
  type        = number
  default     = 443

  validation {
    condition     = var.https_port == floor(var.https_port) && var.https_port >= 1 && var.https_port <= 65535
    error_message = "https_port must be an integer between 1 and 65535."
  }
}

variable "sequence_base" {
  description = "Sequence used by the HTTP rule. HTTPS uses sequence_base + 1."
  type        = number
  default     = 100

  validation {
    condition     = var.sequence_base == floor(var.sequence_base) && var.sequence_base >= 1 && var.sequence_base <= 2147483646
    error_message = "sequence_base must be an integer between 1 and 2147483646."
  }
}

variable "log" {
  description = "Whether accepted packets are logged."
  type        = bool
  default     = false
}

variable "no_xmlrpc_sync" {
  description = "Exclude generated rules from OPNsense HA XMLRPC synchronization."
  type        = bool
  default     = false
}

variable "description_prefix" {
  description = "Prefix used for generated OPNsense rule descriptions."
  type        = string
  default     = "Caddy ingress"

  validation {
    condition = (
      length(var.description_prefix) >= 1 &&
      length(var.description_prefix) <= 220 &&
      can(regex("^[A-Za-z0-9 ._-]+$", var.description_prefix))
    )
    error_message = "description_prefix must contain 1 to 220 ASCII letters, numbers, spaces, dots, underscores, or hyphens."
  }
}
