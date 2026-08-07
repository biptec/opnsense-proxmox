variable "management_interface" {
  description = "Existing logical OPNsense interface backed by the untagged management NIC."
  type        = string
  default     = "lan"
}

variable "management_ipv4_address" {
  description = "Primary management IPv4 address already provisioned by the VM bootstrap, without prefix."
  type        = string
}

variable "management_web_ipv4_cidr" {
  description = "Secondary management IPv4/CIDR used as the WebGUI/API endpoint on the same untagged NIC."
  type        = string
}

variable "management_ssh_ipv6_cidr" {
  description = "Optional IPv6/CIDR for the SSH management identity."
  type        = string
  default     = null
  nullable    = true
}

variable "management_web_ipv6_cidr" {
  description = "Optional IPv6/CIDR for the WebGUI/API management identity."
  type        = string
  default     = null
  nullable    = true
}

variable "trunk_parent_device" {
  description = "FreeBSD device connected to the Proxmox VLAN-aware trunk bridge."
  type        = string
  default     = "vtnet1"
}

variable "webgui_certificate_ref" {
  description = "Existing OPNsense WebGUI certificate ref. Null auto-discovers the current ref through os-api-extensions."
  type        = string
  default     = null
  nullable    = true
}

variable "allow_management_readdress" {
  description = "Explicit approval for disruptive WebGUI/SSH listener changes."
  type        = bool
  default     = false
}

variable "allow_service_readdress" {
  description = "Explicit approval for moving portable services between router loopback and reserved VLAN."
  type        = bool
  default     = false
}

variable "allow_network_readdress" {
  description = "Explicit approval for readdressing an existing routed/WAN assignment."
  type        = bool
  default     = false
}

variable "wan" {
  description = "Primary WAN VLAN and dedicated public identities."
  type = object({
    vlan_id                  = number
    primary_address          = string
    primary_prefix           = number
    gateway                  = string
    public_caddy_address     = string
    public_dns_address       = string
    dedicated_egress_address = string
  })
}

variable "routed_networks" {
  description = "Tagged downstream networks routed by the primary router. Keys are stable inventory identifiers."
  type = map(object({
    vlan_id             = number
    subnet              = string
    router_address      = string
    description         = string
    ipv6_subnet         = optional(string)
    router_ipv6_address = optional(string)
  }))
}

variable "service_networks" {
  description = "Portable router-hosted services. VLAN remains reserved/inactive while hosted_on_router is true."
  type = map(object({
    vlan_id           = number
    subnet            = string
    service_ipv4_host = optional(number, 2)
    ipv6_subnet       = optional(string)
    hosted_on_router  = optional(bool, true)
  }))
}

variable "internal_egress_networks" {
  description = "Internal networks translated through the dedicated Source NAT address."
  type        = set(string)
  default     = ["10.0.0.0/8"]
}

variable "routed_public_subnets" {
  description = "Public routed subnets explicitly excluded from outbound NAT."
  type        = set(string)
}

variable "vpn_client_route" {
  description = "Routed VPN client network reachable through a downstream service gateway."
  type = object({
    network         = string
    via_network_key = string
    gateway_address = string
    gateway_name    = optional(string, "GW_VPN_CLIENTS")
  })
}

variable "ntp_servers" {
  description = "Upstream NTP servers used by the router."
  type = set(object({
    host     = string
    noselect = optional(bool, false)
    prefer   = optional(bool, false)
    iburst   = optional(bool, true)
    pool     = optional(bool, false)
  }))
  default = [
    { host = "0.opnsense.pool.ntp.org", prefer = true, iburst = true, pool = true },
    { host = "1.opnsense.pool.ntp.org", iburst = true, pool = true },
    { host = "2.opnsense.pool.ntp.org", iburst = true, pool = true },
    { host = "3.opnsense.pool.ntp.org", iburst = true, pool = true },
  ]
}

variable "dns_zone" {
  description = "Shared authoritative zone settings owned by the platform state."
  type = object({
    name             = optional(string, "biptec.net")
    primary_ns_label = optional(string, "ns1")
    soa_mail_admin   = optional(string, "hostmaster@biptec.net")
    ttl              = optional(number, 300)
    refresh          = optional(number, 3600)
    retry            = optional(number, 600)
    expire           = optional(number, 1209600)
    negative_ttl     = optional(number, 300)
    dnssec           = optional(bool, true)
  })
  default = {}
}

variable "dns_internal_client_networks" {
  description = "Networks allowed to use the internal BIND view and recursive resolver."
  type        = set(string)
  default     = ["10.0.0.0/8"]

  validation {
    condition = (
      length(var.dns_internal_client_networks) > 0 &&
      alltrue([for network in var.dns_internal_client_networks : can(cidrhost(network, 0))]) &&
      anytrue([for network in var.dns_internal_client_networks : !strcontains(network, ":")])
    )
    error_message = "dns_internal_client_networks must contain valid CIDRs and at least one IPv4 network."
  }
}

variable "cutover" {
  description = "Explicit activation gates. Safe defaults keep public identities detached and retain Unbound as the active DNS owner."
  type = object({
    dns_target                   = optional(string, "unbound")
    allow_dns_cutover            = optional(bool, false)
    dns_verify_timeout           = optional(number, 30)
    management_endpoint_firewall = optional(bool, false)
    public_dns_vip               = optional(bool, false)
    public_caddy_vip             = optional(bool, false)
    caddy_enabled                = optional(bool, false)
    ntp_serving                  = optional(bool, false)
    egress_vip                   = optional(bool, false)
    outbound_nat                 = optional(bool, false)
  })
  default = {}

  validation {
    condition     = contains(["unbound", "bind"], var.cutover.dns_target)
    error_message = "cutover.dns_target must be unbound or bind."
  }

  validation {
    condition     = var.cutover.dns_verify_timeout >= 5 && var.cutover.dns_verify_timeout <= 300
    error_message = "cutover.dns_verify_timeout must be between 5 and 300 seconds."
  }
}
