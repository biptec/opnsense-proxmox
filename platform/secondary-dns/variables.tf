variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint."
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token, supplied outside Git."
}

variable "proxmox_insecure" {
  type        = bool
  default     = false
  description = "Allow an untrusted Proxmox API certificate."
}

variable "node_name" {
  type        = string
  description = "Proxmox node hosting Rigi."
}

variable "vm_id" {
  type        = number
  default     = null
  nullable    = true
  description = "Optional explicit VM ID."
}

variable "vm_datastore" {
  type        = string
  description = "Datastore for the VM disk."
}

variable "image_datastore" {
  type        = string
  default     = "local"
  description = "Datastore supporting Proxmox Import content."
}

variable "snippet_datastore" {
  type        = string
  default     = "local"
  description = "Datastore with Snippets enabled for cloud-init data."
}

variable "cloudinit_datastore" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional Cloud-Init disk datastore; vm_datastore is used when null."
}

variable "image" {
  description = "Pinned Ubuntu 24.04 LTS cloud image."
  type = object({
    url      = string
    sha256   = string
    filename = string
  })
  default = {
    url      = "https://cloud-images.ubuntu.com/releases/noble/release-20260705/ubuntu-24.04-server-cloudimg-amd64.img"
    sha256   = "ffe6203da54deeb6db5d2a98a83f9ec8e55f149d3f7ba622e1abe5fa966ee3d6"
    filename = "ubuntu-24.04-server-cloudimg-amd64-20260705.qcow2"
  }

  validation {
    condition     = can(regex("^https://", var.image.url)) && can(regex("^[0-9a-f]{64}$", var.image.sha256)) && endswith(var.image.filename, ".qcow2")
    error_message = "image must use HTTPS, a lowercase SHA-256 checksum, and a .qcow2 filename."
  }
}

variable "vm" {
  description = "Rigi VM sizing and immutable lifecycle settings."
  type = object({
    name      = optional(string, "rigi")
    cores     = optional(number, 2)
    memory_mb = optional(number, 2048)
    disk_gb   = optional(number, 20)
    on_boot   = optional(bool, true)
    started   = optional(bool, true)
  })
  default = {}
}

variable "bridge" {
  type        = string
  default     = "vmbr1"
  description = "VLAN-aware Proxmox bridge carrying Rigi management access VLAN and service trunk."
}

variable "management_mac" {
  type        = string
  default     = "02:00:05:08:00:01"
  description = "Fixed MAC for the access-VLAN management NIC."
}

variable "trunk_mac" {
  type        = string
  default     = "02:00:38:02:00:01"
  description = "Fixed MAC for the tagged service/public trunk NIC."
}

variable "management" {
  description = "Rigi management network, delivered untagged to the VM through Proxmox access VLAN 508."
  type = object({
    vlan_id      = number
    ipv4_cidr    = string
    ipv4_gateway = string
    ipv6_cidr    = string
    ipv6_gateway = string
  })
}

variable "dns_internal" {
  description = "Alcor/DNS2 internal service VLAN."
  type = object({
    vlan_id      = number
    ipv4_cidr    = string
    ipv4_gateway = string
    ipv6_cidr    = string
    ipv6_gateway = string
  })
}

variable "ntp_internal" {
  description = "Kochab/NTP2 internal service VLAN."
  type = object({
    vlan_id      = number
    ipv4_cidr    = string
    ipv4_gateway = string
    ipv6_cidr    = string
    ipv6_gateway = string
  })
}

variable "public" {
  description = "Routed public transport used only by externally published DNS2."
  type = object({
    vlan_id      = number
    ipv4_cidr    = string
    ipv4_gateway = string
  })
}

variable "primary_router" {
  description = "Etna integration points exported by the primary-router state. The secondary state references shared transport but owns only its own additive router resources."
  type = object({
    trunk_parent_device       = string
    wan_interface             = string
    public_interface          = string
    internal_zone_id          = string
    public_zone_id            = string
    zone_name                 = string
    trusted_internal_networks = set(string)
    internal_dns_ipv4         = string
    public_dns_ipv4           = string
    dns_active_service        = string
  })
}

variable "allow_router_readdress" {
  type        = bool
  default     = false
  description = "Explicit approval for readdressing an existing Rigi-owned OPNsense assignment."
}

variable "transfer_tsig_name" {
  type        = string
  default     = "secondary-transfer.biptec.net"
  description = "TSIG key name shared by the two transferred views."
}

variable "transfer_tsig_algorithm" {
  type        = string
  default     = "hmac-sha256"
  description = "BIND TSIG algorithm."
}

variable "transfer_tsig_secret" {
  type        = string
  sensitive   = true
  description = "Canonical Base64 TSIG secret, supplied outside Git. It is stored in the protected Terraform state and cloud-init snippet."

  validation {
    condition = (
      trimspace(var.transfer_tsig_secret) != "" &&
      length(var.transfer_tsig_secret) % 4 == 0 &&
      can(regex("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$", var.transfer_tsig_secret))
    )
    error_message = "transfer_tsig_secret must be non-empty canonical Base64."
  }
}

variable "ntp_upstreams" {
  type        = set(string)
  default     = ["0.ubuntu.pool.ntp.org", "1.ubuntu.pool.ntp.org", "2.ubuntu.pool.ntp.org", "3.ubuntu.pool.ntp.org"]
  description = "Chrony upstream pools/servers."
}

variable "ssh_public_key" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "Optional public SSH key for the ubuntu account. Password and root SSH remain disabled."
}

variable "internal_recursion_enabled" {
  type        = bool
  default     = true
  description = "Provide recursive resolution on Alcor's trusted internal endpoint. Public DNS2 remains authoritative-only regardless of this value."
}
