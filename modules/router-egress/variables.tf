variable "wan_interface" {
  description = "Existing logical WAN interface that owns the dedicated egress IP Alias."
  type        = string
  default     = "wan"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.wan_interface))
    error_message = "wan_interface must be a lowercase OPNsense logical interface identifier."
  }
}

variable "wan_primary_address" {
  description = "Primary WAN IPv4 address whose prefix provides the connected route for the dedicated /32 egress alias."
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

variable "wan_primary_ipv6_address" {
  description = "Primary WAN IPv6 address whose prefix contains the dedicated NAT66 /128."
  type        = string

  validation {
    condition     = !strcontains(var.wan_primary_ipv6_address, "/") && strcontains(var.wan_primary_ipv6_address, ":") && can(cidrhost("${var.wan_primary_ipv6_address}/128", 0))
    error_message = "wan_primary_ipv6_address must be an IPv6 address without a prefix."
  }
}

variable "wan_primary_ipv6_prefix" {
  description = "IPv6 prefix length of the primary WAN address."
  type        = number

  validation {
    condition     = var.wan_primary_ipv6_prefix == 64
    error_message = "wan_primary_ipv6_prefix must be 64 for the Hetzner WAN subnet."
  }
}

variable "wan_primary_prefix" {
  description = "IPv4 prefix length of the primary WAN address."
  type        = number

  validation {
    condition     = var.wan_primary_prefix == floor(var.wan_primary_prefix) && var.wan_primary_prefix >= 1 && var.wan_primary_prefix <= 32
    error_message = "wan_primary_prefix must be an integer from 1 to 32."
  }
}

variable "wan_gateway" {
  description = "Provider-facing IPv4 gateway that must be on-link through the primary WAN prefix."
  type        = string

  validation {
    condition = (
      !strcontains(var.wan_gateway, "/") &&
      can(cidrnetmask("${var.wan_gateway}/32")) &&
      var.wan_gateway != "0.0.0.0" &&
      !startswith(var.wan_gateway, "127.")
    )
    error_message = "wan_gateway must be a non-wildcard IPv4 address without a prefix."
  }
}

variable "dedicated_egress_address" {
  description = "Dedicated public IPv4 address used only as the outbound NAT source."
  type        = string

  validation {
    condition = (
      !strcontains(var.dedicated_egress_address, "/") &&
      can(cidrnetmask("${var.dedicated_egress_address}/32")) &&
      var.dedicated_egress_address != "0.0.0.0" &&
      !startswith(var.dedicated_egress_address, "127.")
    )
    error_message = "dedicated_egress_address must be a non-wildcard IPv4 address without a prefix."
  }
}

variable "dedicated_egress_ipv6_address" {
  description = "Dedicated public IPv6 /128 used only as the stateful outbound NAT66 source."
  type        = string

  validation {
    condition     = !strcontains(var.dedicated_egress_ipv6_address, "/") && strcontains(var.dedicated_egress_ipv6_address, ":") && can(cidrhost("${var.dedicated_egress_ipv6_address}/128", 0))
    error_message = "dedicated_egress_ipv6_address must be an IPv6 address without a prefix."
  }
}

variable "reserved_addresses" {
  description = "Existing management, primary WAN, public service, and internal service IPv4 addresses that the egress identity must not reuse."
  type        = set(string)

  validation {
    condition = alltrue([
      for address in var.reserved_addresses :
      !strcontains(address, "/") &&
      can(cidrnetmask("${address}/32")) &&
      address != "0.0.0.0" &&
      !startswith(address, "127.")
    ])
    error_message = "reserved_addresses must contain IPv4 addresses without prefixes."
  }
}

variable "reserved_ipv6_addresses" {
  description = "Existing primary WAN, public service, internal service, and routed IPv6 addresses that the NAT66 identity must not reuse."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for address in var.reserved_ipv6_addresses :
      !strcontains(address, "/") && strcontains(address, ":") && can(cidrhost("${address}/128", 0))
    ])
    error_message = "reserved_ipv6_addresses must contain IPv6 addresses without prefixes."
  }
}

variable "service_binding_guard" {
  description = "Dependency token from router-services. It must be non-empty before an additional WAN VIP may be attached."
  type        = string
  default     = ""
}

variable "public_egress_vip_enabled" {
  description = "Attach the dedicated egress /32 IP Alias to WAN. Keep false until outbound NAT cutover is ready."
  type        = bool
  default     = false
}

variable "outbound_nat_enabled" {
  description = "Manage hybrid outbound NAT, routed-public NO-NAT rules, and the dedicated egress translation rule."
  type        = bool
  default     = false
}

variable "internal_egress_networks" {
  description = "Internal canonical IPv4 CIDR networks translated through the dedicated egress address."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for subnet in var.internal_egress_networks :
      can(cidrnetmask(subnet)) &&
      try(cidrhost(subnet, 0), "") == try(split("/", subnet)[0], "invalid")
    ])
    error_message = "internal_egress_networks must contain canonical IPv4 CIDR network addresses."
  }
}

variable "internal_egress_ipv6_networks" {
  description = "Canonical internal IPv6 CIDRs translated statefully through the dedicated NAT66 address."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for subnet in var.internal_egress_ipv6_networks :
      strcontains(subnet, ":") && can(cidrhost(subnet, 0)) &&
      try(cidrhost(subnet, 0), "") == try(split("/", subnet)[0], "invalid")
    ])
    error_message = "internal_egress_ipv6_networks must contain canonical IPv6 CIDR network addresses."
  }
}

variable "internal_egress_ipv6_alias_name" {
  description = "OPNsense alias name used by the stateful NAT66 rule."
  type        = string
  default     = "INTERNAL_EGRESS_V6"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]{0,31}$", var.internal_egress_ipv6_alias_name))
    error_message = "internal_egress_ipv6_alias_name must be a valid OPNsense alias name up to 32 characters."
  }
}

variable "internal_egress_alias_name" {
  description = "OPNsense alias name used by the dedicated outbound NAT rule."
  type        = string
  default     = "INTERNAL_EGRESS_NETWORKS"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]{0,31}$", var.internal_egress_alias_name))
    error_message = "internal_egress_alias_name must be a valid OPNsense alias name up to 32 characters."
  }
}

variable "routed_public_subnets" {
  description = "Canonical public IPv4 CIDR subnets routed to workloads and explicitly excluded from outbound NAT."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for subnet in var.routed_public_subnets :
      can(cidrnetmask(subnet)) &&
      try(cidrhost(subnet, 0), "") == try(split("/", subnet)[0], "invalid")
    ])
    error_message = "routed_public_subnets must contain canonical IPv4 CIDR network addresses."
  }
}

variable "routed_public_ipv6_subnets" {
  description = "Canonical routed-public IPv6 CIDRs explicitly excluded from stateful NAT66."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for subnet in var.routed_public_ipv6_subnets :
      strcontains(subnet, ":") && can(cidrhost(subnet, 0)) &&
      try(cidrhost(subnet, 0), "") == try(split("/", subnet)[0], "invalid")
    ])
    error_message = "routed_public_ipv6_subnets must contain canonical IPv6 CIDR network addresses."
  }
}

variable "no_nat_ipv6_sequence_base" {
  description = "First outbound NAT sequence allocated to routed-public IPv6 NO-NAT rules."
  type        = number
  default     = 905000
}

variable "no_nat_sequence_base" {
  description = "First outbound NAT sequence allocated to routed-public NO-NAT rules."
  type        = number
  default     = 900000

  validation {
    condition     = var.no_nat_sequence_base == floor(var.no_nat_sequence_base) && var.no_nat_sequence_base >= 1
    error_message = "no_nat_sequence_base must be a positive integer."
  }
}

variable "egress_ipv6_nat_sequence" {
  description = "Outbound NAT sequence for the stateful internal IPv6 translation rule."
  type        = number
  default     = 915000

  validation {
    condition     = var.egress_ipv6_nat_sequence == floor(var.egress_ipv6_nat_sequence) && var.egress_ipv6_nat_sequence >= 1
    error_message = "egress_ipv6_nat_sequence must be a positive integer."
  }
}

variable "egress_nat_sequence" {
  description = "Outbound NAT sequence for the dedicated internal egress translation rule."
  type        = number
  default     = 910000

  validation {
    condition     = var.egress_nat_sequence == floor(var.egress_nat_sequence) && var.egress_nat_sequence >= 1
    error_message = "egress_nat_sequence must be a positive integer."
  }
}
