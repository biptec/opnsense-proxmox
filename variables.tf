variable "proxmox_endpoint" {
  description = "Base URL of the Proxmox VE API, including the port, for example https://host.example.net:8006/."
  type        = string

  validation {
    condition     = trimspace(var.proxmox_endpoint) != ""
    error_message = "proxmox_endpoint must not be empty."
  }
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the form user@realm!token-id=token-secret. Store it in token.auto.tfvars or TF_VAR_proxmox_api_token."
  type        = string
  sensitive   = true

  validation {
    condition     = trimspace(var.proxmox_api_token) != ""
    error_message = "proxmox_api_token must not be empty."
  }
}

variable "proxmox_insecure" {
  description = "Skip TLS certificate verification for the Proxmox API. Keep false when the API certificate is trusted."
  type        = bool
  default     = false
}

variable "node_name" {
  description = "Name of the Proxmox node on which the VM and uploaded image will be created."
  type        = string

  validation {
    condition     = trimspace(var.node_name) != ""
    error_message = "node_name must not be empty."
  }
}

variable "vm_id" {
  description = "Optional numeric VM ID. When null, Proxmox allocates the next available ID."
  type        = number
  default     = null

  validation {
    condition     = var.vm_id == null || (var.vm_id >= 100 && var.vm_id <= 999999999)
    error_message = "vm_id must be null or a valid Proxmox VM ID from 100 to 999999999."
  }
}

variable "vm_name" {
  description = "Display name of the VM. Proxmox also uses it as the Cloud-Init hostname unless overridden elsewhere."
  type        = string
  default     = "opnsense"

  validation {
    condition     = trimspace(var.vm_name) != ""
    error_message = "vm_name must not be empty."
  }
}

variable "image_source" {
  description = "Image source mode: local uploads image_path from the OpenTofu runner; proxmox uses an existing Proxmox import file identified by image_file_id."
  type        = string
  default     = "local"

  validation {
    condition     = contains(["local", "proxmox"], var.image_source)
    error_message = "image_source must be either local or proxmox."
  }
}

variable "image_datastore" {
  description = "File-based Proxmox datastore used only in local image mode to store the uploaded source image as content type import."
  type        = string
  default     = "local"
}

variable "vm_datastore" {
  description = "Proxmox datastore for the imported VM system disk. This datastore must support images."
  type        = string

  validation {
    condition     = trimspace(var.vm_datastore) != ""
    error_message = "vm_datastore must not be empty."
  }
}

variable "cloudinit_datastore" {
  description = "Optional datastore for the Cloud-Init drive. When null, vm_datastore is used."
  type        = string
  default     = null
}

variable "image_path" {
  description = "Optional local path to the QCOW2 or raw source image. Required only when image_source is local."
  type        = string
  default     = null

  validation {
    condition     = var.image_path == null || trimspace(var.image_path) != ""
    error_message = "image_path must be null or a non-empty path."
  }
}

variable "image_file_id" {
  description = "Optional Proxmox file ID of an existing import image, for example local:import/OPNsense.qcow2. Required only when image_source is proxmox."
  type        = string
  default     = null

  validation {
    condition     = var.image_file_id == null || can(regex("^[^:]+:import/.+$", var.image_file_id))
    error_message = "image_file_id must be null or use the format <datastore>:import/<file-name>."
  }
}

variable "image_sha256" {
  description = "Optional SHA-256 checksum of image_path. It is used only when image_source is local."
  type        = string
  default     = null

  validation {
    condition     = var.image_sha256 == null || can(regex("^[0-9a-fA-F]{64}$", var.image_sha256))
    error_message = "image_sha256 must be null or a 64-character hexadecimal SHA-256 value."
  }
}

variable "bridge" {
  description = "Proxmox Linux bridge connected to the management network."
  type        = string
  default     = "vmbr0"
}

variable "management_mac" {
  description = "Optional fixed MAC address for the management NIC. When null, Proxmox generates one."
  type        = string
  default     = null

  validation {
    condition     = var.management_mac == null || can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", var.management_mac))
    error_message = "management_mac must be null or a colon-separated MAC address."
  }
}

variable "management_vlan_id" {
  description = "Optional VLAN tag applied by Proxmox to the management NIC. Null means untagged traffic."
  type        = number
  default     = null

  validation {
    condition     = var.management_vlan_id == null || (var.management_vlan_id >= 1 && var.management_vlan_id <= 4094)
    error_message = "management_vlan_id must be null or a VLAN ID from 1 to 4094."
  }
}

variable "management_address" {
  description = "Static IPv4 management address in CIDR notation passed through the Proxmox NoCloud network configuration."
  type        = string

  validation {
    condition     = can(cidrhost(var.management_address, 0)) && !strcontains(var.management_address, ":")
    error_message = "management_address must be a valid IPv4 CIDR, for example 10.200.0.50/24."
  }
}

variable "management_gateway" {
  description = "Optional IPv4 default gateway for the management interface. Null creates no default route."
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "Optional DNS server addresses included in the Cloud-Init data."
  type        = list(string)
  default     = []
}

variable "dns_domain" {
  description = "Optional DNS search domain. Together with vm_name it forms the guest FQDN."
  type        = string
  default     = null
}

variable "ssh_public_key_path" {
  description = "Optional local path to an SSH public key installed for root through Cloud-Init."
  type        = string
  default     = null
}

variable "ssh_private_key_path" {
  description = "Optional local path to the matching SSH private key. Required only when wait_for_api is true."
  type        = string
  default     = null
}

variable "wait_for_api" {
  description = "After VM creation, connect over SSH, retrieve bootstrap API credentials, and wait for the OPNsense API."
  type        = bool
  default     = false
}

variable "api_scheme" {
  description = "URL scheme used by the API readiness check."
  type        = string
  default     = "https"

  validation {
    condition     = contains(["http", "https"], var.api_scheme)
    error_message = "api_scheme must be http or https."
  }
}

variable "api_credentials_path" {
  description = "Local output path for bootstrap API credentials when wait_for_api is enabled."
  type        = string
  default     = "./bootstrap-api.json"
}

variable "cores" {
  description = "Number of virtual CPU cores assigned to the VM."
  type        = number
  default     = 4

  validation {
    condition     = var.cores >= 1
    error_message = "cores must be at least 1."
  }
}

variable "memory_mb" {
  description = "Dedicated VM memory in MiB."
  type        = number
  default     = 4096

  validation {
    condition     = var.memory_mb >= 512
    error_message = "memory_mb must be at least 512 MiB."
  }
}

variable "disk_size_gb" {
  description = "System disk size in GiB after import. It must not be smaller than the virtual size of the source image."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 1
    error_message = "disk_size_gb must be at least 1 GiB."
  }
}

variable "additional_nics" {
  description = "Optional additional VirtIO NICs. Their MAC addresses and VLAN IDs may also be omitted."
  type = list(object({
    bridge      = string
    mac_address = optional(string)
    vlan_id     = optional(number)
  }))
  default = []
}
