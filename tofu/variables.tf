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
  description = "Optional local path to an SSH public key installed for cloudinit_username through NoCloud."
  type        = string
  default     = null
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
  default     = 21

  validation {
    condition     = var.disk_size_gb >= 1
    error_message = "disk_size_gb must be at least 1 GiB."
  }
}

variable "additional_nics" {
  description = "Optional additional NICs. Every Proxmox NIC setting can be overridden per interface."
  type = list(object({
    bridge       = string
    model        = optional(string)
    mac_address  = optional(string)
    vlan_id      = optional(number)
    disconnected = optional(bool)
    firewall     = optional(bool)
    mtu          = optional(number)
    queues       = optional(number)
    rate_limit   = optional(number)
    trunks       = optional(string)
  }))
  default = []
}


variable "vm_description" {
  description = "Description stored in the Proxmox VM configuration."
  type        = string
  default     = "Managed by OpenTofu"
}

variable "vm_tags" {
  description = "Proxmox metadata tags assigned to the VM."
  type        = list(string)
  default     = ["opnsense", "managed"]
}

variable "vm_started" {
  description = "Whether the VM should be running after apply."
  type        = bool
  default     = true
}

variable "vm_on_boot" {
  description = "Whether Proxmox should start the VM when the node boots."
  type        = bool
  default     = true
}

variable "vm_stop_on_destroy" {
  description = "Whether the provider should force-stop rather than gracefully shut down the VM during destroy."
  type        = bool
  default     = true
}

variable "vm_acpi" {
  description = "Optional ACPI setting. Null uses the provider default."
  type        = bool
  default     = null
}

variable "vm_bios" {
  description = "Optional BIOS implementation, for example seabios or ovmf. Null uses the provider default."
  type        = string
  default     = null
}

variable "vm_delete_unreferenced_disks_on_destroy" {
  description = "Optional setting controlling deletion of unreferenced disks during destroy. Null uses the provider default."
  type        = bool
  default     = null
}

variable "vm_hook_script_file_id" {
  description = "Optional Proxmox hook script file ID."
  type        = string
  default     = null
}

variable "vm_hotplug" {
  description = "Optional Proxmox hotplug feature expression."
  type        = string
  default     = null
}

variable "vm_keyboard_layout" {
  description = "Optional keyboard layout for the VM console."
  type        = string
  default     = null
}

variable "vm_kvm_arguments" {
  description = "Optional additional KVM command-line arguments."
  type        = string
  default     = null
}

variable "vm_migrate" {
  description = "Optional setting to migrate the VM when node_name changes instead of recreating it."
  type        = bool
  default     = null
}

variable "vm_pool_id" {
  description = "Optional Proxmox pool ID to which the VM is assigned."
  type        = string
  default     = null
}

variable "vm_protection" {
  description = "Optional Proxmox protection flag preventing VM and disk removal."
  type        = bool
  default     = null
}

variable "vm_purge_on_destroy" {
  description = "Optional setting controlling removal from backup jobs during destroy."
  type        = bool
  default     = null
}

variable "vm_reboot" {
  description = "Optional reboot request managed by the provider. Null leaves it unset."
  type        = bool
  default     = null
}

variable "vm_reboot_after_update" {
  description = "Optional permission for the provider to reboot the VM when an update requires it."
  type        = bool
  default     = null
}

variable "vm_tablet_device" {
  description = "Optional USB tablet device setting. Null uses the provider default."
  type        = bool
  default     = null
}

variable "vm_template" {
  description = "Optional setting to convert the VM into a Proxmox template."
  type        = bool
  default     = null
}

variable "vm_machine" {
  description = "QEMU machine type used by the VM, for example q35 or pc."
  type        = string
  default     = "q35"
}

variable "vm_scsi_hardware" {
  description = "Emulated SCSI controller model used by the VM."
  type        = string
  default     = "virtio-scsi-single"
}

variable "vm_boot_order" {
  description = "Ordered list of devices from which the VM attempts to boot."
  type        = list(string)
  default     = ["scsi0"]
}

variable "qemu_agent_enabled" {
  description = "Enable the QEMU guest agent integration in the Proxmox VM configuration."
  type        = bool
  default     = true
}

variable "qemu_agent_timeout" {
  description = "Maximum time to wait for data from the QEMU guest agent. Null uses the provider default."
  type        = string
  default     = null
}

variable "qemu_agent_trim" {
  description = "Optional QEMU guest agent FSTRIM setting. Null uses the provider default."
  type        = bool
  default     = null
}

variable "qemu_agent_type" {
  description = "QEMU guest agent interface type exposed to the VM."
  type        = string
  default     = "virtio"
}

variable "qemu_agent_wait_for_ip" {
  description = "QEMU agent IP wait settings. The default keeps the agent enabled without blocking apply while the guest boots."
  type = object({
    disabled = optional(bool)
    ipv4     = optional(bool)
    ipv6     = optional(bool)
  })
  default = {
    disabled = true
    ipv4     = false
    ipv6     = false
  }
}

variable "cpu_type" {
  description = "Emulated CPU type exposed to the VM, for example host or x86-64-v2-AES."
  type        = string
  default     = "host"
}

variable "cpu_sockets" {
  description = "Optional number of virtual CPU sockets. Null uses the provider default."
  type        = number
  default     = null
}

variable "cpu_architecture" {
  description = "Optional CPU architecture override. Null uses the provider default."
  type        = string
  default     = null
}

variable "cpu_affinity" {
  description = "Optional Proxmox CPU affinity expression."
  type        = string
  default     = null
}

variable "cpu_flags" {
  description = "Optional CPU feature flags passed to the VM. Null leaves them unset."
  type        = list(string)
  default     = null
}

variable "cpu_hotplugged" {
  description = "Optional number of hotplugged virtual CPUs. Null uses the provider default."
  type        = number
  default     = null
}

variable "cpu_limit" {
  description = "Optional CPU usage limit. Null leaves it unset."
  type        = number
  default     = null
}

variable "cpu_numa" {
  description = "Optional NUMA setting. Null uses the provider default."
  type        = bool
  default     = null
}

variable "cpu_units" {
  description = "Optional relative CPU weight. Null uses the provider default."
  type        = number
  default     = null
}

variable "memory_floating_mb" {
  description = "Optional balloon memory in MiB. Null uses the provider default."
  type        = number
  default     = null
}

variable "memory_hugepages" {
  description = "Optional hugepages mode, for example any, 2 or 1024. Null disables an explicit override."
  type        = string
  default     = null
}

variable "memory_keep_hugepages" {
  description = "Optional setting to keep hugepages allocated after shutdown. Null uses the provider default."
  type        = bool
  default     = null
}

variable "memory_shared_mb" {
  description = "Optional shared memory amount in MiB. Null uses the provider default."
  type        = number
  default     = null
}

variable "disk_interface" {
  description = "Proxmox interface name for the imported system disk."
  type        = string
  default     = "scsi0"
}

variable "disk_aio" {
  description = "Optional asynchronous I/O mode for the system disk."
  type        = string
  default     = null
}

variable "disk_backup" {
  description = "Optional setting controlling inclusion of the system disk in backups. Null uses the provider default."
  type        = bool
  default     = null
}

variable "disk_cache" {
  description = "Optional cache mode for the system disk. Null uses the provider default."
  type        = string
  default     = null
}

variable "disk_discard" {
  description = "Discard/TRIM mode for the system disk."
  type        = string
  default     = "on"
}

variable "disk_iothread" {
  description = "Optional I/O thread setting for the system disk. Null uses the provider default."
  type        = bool
  default     = null
}

variable "disk_queues" {
  description = "Optional number of I/O queues for the system disk."
  type        = number
  default     = null
}

variable "disk_replicate" {
  description = "Optional replication setting for the system disk. Null uses the provider default."
  type        = bool
  default     = null
}

variable "disk_serial" {
  description = "Optional serial number exposed by the system disk."
  type        = string
  default     = null
}

variable "disk_ssd" {
  description = "Expose the system disk as SSD to the guest."
  type        = bool
  default     = true
}

variable "disk_speed" {
  description = "Optional system disk I/O limits. Null omits the speed block."
  type = object({
    iops_read            = optional(number)
    iops_read_burstable  = optional(number)
    iops_write           = optional(number)
    iops_write_burstable = optional(number)
    read                 = optional(number)
    read_burstable       = optional(number)
    write                = optional(number)
    write_burstable      = optional(number)
  })
  default = null
}

variable "cloudinit_username" {
  description = "Key-only administrative user created by the OPNsense NoCloud bootstrap."
  type        = string
  default     = "proxmox"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.cloudinit_username)) && var.cloudinit_username != "root"
    error_message = "cloudinit_username must be a valid non-root Unix username."
  }
}

variable "cloudinit_interface" {
  description = "Optional Proxmox interface for the Cloud-Init drive. Null uses the provider default."
  type        = string
  default     = null
}

variable "cloudinit_type" {
  description = "Optional Cloud-Init format override. Null uses the provider default."
  type        = string
  default     = null
}

variable "cloudinit_upgrade" {
  description = "Optional first-boot package upgrade setting. Null uses the provider default."
  type        = bool
  default     = null
}

variable "network_model" {
  description = "Default emulated NIC model for the management and additional interfaces."
  type        = string
  default     = "virtio"
}

variable "management_nic_enabled" {
  description = "Optional enabled state for the management NIC. Null uses the provider default."
  type        = bool
  default     = null
}

variable "management_nic_disconnected" {
  description = "Optional disconnected state for the management NIC. Null uses the provider default."
  type        = bool
  default     = null
}

variable "management_nic_firewall" {
  description = "Optional Proxmox firewall setting for the management NIC. Null uses the provider default."
  type        = bool
  default     = null
}

variable "management_nic_mtu" {
  description = "Optional MTU configured for the management NIC."
  type        = number
  default     = null
}

variable "management_nic_queues" {
  description = "Optional number of multiqueue queues for the management NIC."
  type        = number
  default     = null
}

variable "management_nic_rate_limit" {
  description = "Optional management NIC rate limit in megabytes per second."
  type        = number
  default     = null
}

variable "management_nic_trunks" {
  description = "Optional VLAN trunk expression for the management NIC."
  type        = string
  default     = null
}

variable "operating_system_type" {
  description = "Proxmox guest operating system type."
  type        = string
  default     = "other"
}

variable "serial_device_enabled" {
  description = "Attach a serial console device to the VM."
  type        = bool
  default     = true
}

variable "serial_device" {
  description = "Serial device backend, normally socket for the Proxmox serial console."
  type        = string
  default     = "socket"
}
