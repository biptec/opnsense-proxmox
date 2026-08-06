variable "management_interface" {
  description = "Existing logical interface used exclusively by WebGUI/API and SSH."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.management_interface))
    error_message = "management_interface must be a lowercase OPNsense logical interface identifier."
  }
}

variable "management_address" {
  description = "Existing management IPv4 address used only to prevent service-network reuse."
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

variable "trunk_parent_device" {
  description = "Physical trunk device that carries all service VLANs."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9_.:-]*$", var.trunk_parent_device))
    error_message = "trunk_parent_device must be a valid lowercase FreeBSD interface name."
  }
}

variable "reserved_vlan_ids" {
  description = "VLAN IDs already owned by WAN, tenant, or other platform networks."
  type        = set(number)
  default     = []

  validation {
    condition = alltrue([
      for vlan_id in var.reserved_vlan_ids :
      vlan_id == floor(vlan_id) && vlan_id >= 1 && vlan_id <= 4094
    ])
    error_message = "reserved_vlan_ids must contain integer VLAN IDs from 1 through 4094."
  }
}

variable "allow_management_readdress" {
  description = "Explicitly permit WebGUI/API and SSH listener changes that may interrupt management access."
  type        = bool
  default     = false
}

variable "webgui" {
  description = "WebGUI/API listener configuration. The timeout is expressed in native OPNsense minutes."
  type = object({
    protocol                = optional(string, "https")
    port                    = optional(number, 443)
    certificate_ref         = optional(string, "")
    session_timeout_minutes = optional(number)
    hsts                    = optional(bool, true)
    disable_http_redirect   = optional(bool, false)
    alternate_hostnames     = optional(set(string), [])
  })
  default = {}

  validation {
    condition     = contains(["http", "https"], var.webgui.protocol)
    error_message = "webgui.protocol must be http or https."
  }

  validation {
    condition     = var.webgui.port == floor(var.webgui.port) && var.webgui.port >= 1 && var.webgui.port <= 65535
    error_message = "webgui.port must be an integer between 1 and 65535."
  }

  validation {
    condition = (
      var.webgui.session_timeout_minutes == null ||
      (
        var.webgui.session_timeout_minutes == floor(var.webgui.session_timeout_minutes) &&
        var.webgui.session_timeout_minutes >= 1 &&
        var.webgui.session_timeout_minutes <= 86400
      )
    )
    error_message = "webgui.session_timeout_minutes must be a positive integer no greater than 86400."
  }

  validation {
    condition     = var.webgui.protocol != "https" || trimspace(var.webgui.certificate_ref) != ""
    error_message = "webgui.certificate_ref must be set when webgui.protocol is https."
  }
}

variable "ssh" {
  description = "SSH listener configuration."
  type = object({
    enabled                 = optional(bool, true)
    port                    = optional(number, 22)
    password_authentication = optional(bool, false)
    permit_root_login       = optional(bool, false)
  })
  default = {}

  validation {
    condition     = var.ssh.port == floor(var.ssh.port) && var.ssh.port >= 1 && var.ssh.port <= 65535
    error_message = "ssh.port must be an integer between 1 and 65535."
  }
}

variable "allow_service_readdress" {
  description = "Explicitly permit changes to a permanent service VLAN assignment or router gateway address."
  type        = bool
  default     = false
}

variable "service_networks" {
  description = "One VLAN and one canonical IPv4 /30 per movable service. Host .1 is the permanent router gateway and host .2 is the service address."
  type = map(object({
    vlan_id          = number
    subnet           = string
    hosted_on_router = optional(bool, true)
  }))

  validation {
    condition = (
      length(var.service_networks) > 0 &&
      alltrue([for name in keys(var.service_networks) : can(regex("^[a-z][a-z0-9_]*$", name))])
    )
    error_message = "service_networks must contain at least one lowercase service name."
  }

  validation {
    condition = (
      length(toset([for network in values(var.service_networks) : network.subnet])) == length(var.service_networks) &&
      length(toset([for network in values(var.service_networks) : tostring(network.vlan_id)])) == length(var.service_networks)
    )
    error_message = "Every service must use a unique /30 and a unique VLAN ID."
  }

  validation {
    condition = alltrue([
      for network in values(var.service_networks) :
      network.vlan_id == floor(network.vlan_id) &&
      network.vlan_id >= 1 && network.vlan_id <= 4094 &&
      !contains(var.reserved_vlan_ids, network.vlan_id)
    ])
    error_message = "Service VLAN IDs must be integers from 1 through 4094 and must not be reserved."
  }

  validation {
    condition = alltrue([
      for network in values(var.service_networks) :
      can(cidrnetmask(network.subnet)) &&
      try(tonumber(split("/", network.subnet)[1]), 0) == 30 &&
      try(cidrhost(network.subnet, 0), "") == try(split("/", network.subnet)[0], "invalid")
    ])
    error_message = "Every service subnet must be a canonical IPv4 /30 network address."
  }
}
