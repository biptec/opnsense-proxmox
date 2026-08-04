variable "acme_email" {
  description = "Email address used by Caddy for public ACME accounts."
  type        = string
  default     = "webmaster@biptec.com"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+$", var.acme_email))
    error_message = "acme_email must be a valid non-empty email address."
  }
}

variable "ingress_interface" {
  description = "Logical OPNsense interface receiving public HTTP and HTTPS traffic."
  type        = string
  default     = "wan"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.ingress_interface))
    error_message = "ingress_interface must be a lowercase OPNsense logical identifier."
  }
}

variable "ingress_destination" {
  description = "Optional destination address or alias. Null uses <ingress_interface>ip."
  type        = string
  default     = null

  validation {
    condition     = var.ingress_destination == null || trimspace(var.ingress_destination) != ""
    error_message = "ingress_destination must be null or a non-empty address or alias."
  }
}

variable "ingress_source_network" {
  description = "Source address, CIDR, or alias allowed to reach Caddy."
  type        = string
  default     = "any"

  validation {
    condition     = trimspace(var.ingress_source_network) != ""
    error_message = "ingress_source_network must not be empty."
  }
}

variable "ingress_sequence_base" {
  description = "Firewall sequence for HTTP. HTTPS uses the next sequence."
  type        = number
  default     = 100

  validation {
    condition     = var.ingress_sequence_base == floor(var.ingress_sequence_base) && var.ingress_sequence_base >= 1
    error_message = "ingress_sequence_base must be a positive integer."
  }
}

variable "log_ingress" {
  description = "Log packets accepted by the global HTTP and HTTPS rules."
  type        = bool
  default     = false
}

variable "caddy_log_level" {
  description = "Global Caddy log level. Empty uses INFO."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "DEBUG", "WARN", "ERROR", "PANIC", "FATAL"], var.caddy_log_level)
    error_message = "caddy_log_level must be empty, DEBUG, WARN, ERROR, PANIC, or FATAL."
  }
}
