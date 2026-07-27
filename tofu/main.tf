locals {
  # Keep repeated and mode-dependent values in one place.
  cloudinit_datastore_id = coalesce(var.cloudinit_datastore, var.vm_datastore)

  # Pre-hash the bootstrap password with a crypt format supported by both
  # Proxmox and OPNsense. This avoids depending on the host's crypt default.
  cloudinit_password_hash = var.cloudinit_password == null ? null : bcrypt(var.cloudinit_password)

  # Both modes produce the same Proxmox file ID consumed by disk.import_from.
  # local mode gets it from the upload resource; proxmox mode uses the supplied ID.
  source_image_file_id = var.image_source == "local" ? proxmox_virtual_environment_file.image[0].id : var.image_file_id
}

# Preserve the existing state address after renaming the resource to a name that
# clearly describes the VM rather than suggesting that Proxmox firewall is used.
moved {
  from = proxmox_virtual_environment_vm.firewall
  to   = proxmox_virtual_environment_vm.opnsense
}

# Upload the source disk only in local mode. In proxmox mode count is zero and
# OpenTofu leaves the existing Proxmox import file unmanaged and unchanged.
resource "proxmox_virtual_environment_file" "image" {
  count = var.image_source == "local" ? 1 : 0

  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.node_name
  overwrite    = false

  source_file {
    # Fallback values keep the zero-count proxmox mode type-safe. In local mode
    # the precondition below requires image_path to reference a real file.
    path      = coalesce(var.image_path, "IMAGE_PATH_REQUIRED")
    checksum  = var.image_sha256
    file_name = var.image_path == null ? "IMAGE_PATH_REQUIRED.qcow2" : basename(var.image_path)
  }

  lifecycle {
    precondition {
      condition     = var.image_path != null && try(fileexists(var.image_path), false)
      error_message = "image_source=local requires image_path to reference an existing local image file."
    }
  }
}

# Create the OPNsense virtual machine. Every explicitly managed VM option is
# backed by a variable, so environment-specific choices belong in tfvars.
resource "proxmox_virtual_environment_vm" "opnsense" {
  name        = var.vm_name
  description = var.vm_description
  tags        = var.vm_tags

  node_name       = var.node_name
  vm_id           = var.vm_id
  started         = var.vm_started
  on_boot         = var.vm_on_boot
  stop_on_destroy = var.vm_stop_on_destroy

  acpi                                 = var.vm_acpi
  bios                                 = var.vm_bios
  delete_unreferenced_disks_on_destroy = var.vm_delete_unreferenced_disks_on_destroy
  hook_script_file_id                  = var.vm_hook_script_file_id
  hotplug                              = var.vm_hotplug
  keyboard_layout                      = var.vm_keyboard_layout
  kvm_arguments                        = var.vm_kvm_arguments
  migrate                              = var.vm_migrate
  pool_id                              = var.vm_pool_id
  protection                           = var.vm_protection
  purge_on_destroy                     = var.vm_purge_on_destroy
  reboot                               = var.vm_reboot
  reboot_after_update                  = var.vm_reboot_after_update
  tablet_device                        = var.vm_tablet_device
  template                             = var.vm_template

  machine       = var.vm_machine
  scsi_hardware = var.vm_scsi_hardware
  boot_order    = var.vm_boot_order

  agent {
    enabled = var.qemu_agent_enabled
    timeout = var.qemu_agent_timeout
    trim    = var.qemu_agent_trim
    type    = var.qemu_agent_type

    dynamic "wait_for_ip" {
      for_each = var.qemu_agent_wait_for_ip == null ? [] : [var.qemu_agent_wait_for_ip]
      content {
        disabled = wait_for_ip.value.disabled
        ipv4     = wait_for_ip.value.ipv4
        ipv6     = wait_for_ip.value.ipv6
      }
    }
  }

  cpu {
    cores        = var.cores
    type         = var.cpu_type
    sockets      = var.cpu_sockets
    architecture = var.cpu_architecture
    affinity     = var.cpu_affinity
    flags        = var.cpu_flags
    hotplugged   = var.cpu_hotplugged
    limit        = var.cpu_limit
    numa         = var.cpu_numa
    units        = var.cpu_units
  }

  memory {
    dedicated      = var.memory_mb
    floating       = var.memory_floating_mb
    hugepages      = var.memory_hugepages
    keep_hugepages = var.memory_keep_hugepages
    shared         = var.memory_shared_mb
  }

  # import_from accepts either the file uploaded above or an existing Proxmox
  # import file. On ZFS-backed storage the resulting VM disk is a raw zvol.
  disk {
    datastore_id = var.vm_datastore
    import_from  = local.source_image_file_id
    interface    = var.disk_interface
    size         = var.disk_size_gb
    aio          = var.disk_aio
    backup       = var.disk_backup
    cache        = var.disk_cache
    discard      = var.disk_discard
    iothread     = var.disk_iothread
    queues       = var.disk_queues
    replicate    = var.disk_replicate
    serial       = var.disk_serial
    ssd          = var.disk_ssd

    dynamic "speed" {
      for_each = var.disk_speed == null ? [] : [var.disk_speed]
      content {
        iops_read            = speed.value.iops_read
        iops_read_burstable  = speed.value.iops_read_burstable
        iops_write           = speed.value.iops_write
        iops_write_burstable = speed.value.iops_write_burstable
        read                 = speed.value.read
        read_burstable       = speed.value.read_burstable
        write                = speed.value.write
        write_burstable      = speed.value.write_burstable
      }
    }
  }

  # Proxmox generates a NoCloud drive. The custom OPNsense bootstrap reads it
  # on first boot and applies hostname, network, DNS and optional credentials.
  initialization {
    datastore_id = local.cloudinit_datastore_id
    interface    = var.cloudinit_interface
    type         = var.cloudinit_type
    upgrade      = var.cloudinit_upgrade

    dynamic "dns" {
      for_each = var.dns_domain == null && length(var.dns_servers) == 0 ? [] : [1]
      content {
        domain  = var.dns_domain
        servers = var.dns_servers
      }
    }

    dynamic "ip_config" {
      for_each = var.management_ipv4.mode == "preserve" ? [] : [var.management_ipv4]
      content {
        ipv4 {
          address = ip_config.value.mode == "dhcp" ? "dhcp" : ip_config.value.address
          gateway = ip_config.value.mode == "static" ? ip_config.value.gateway : null
        }
      }
    }

    dynamic "user_account" {
      for_each = var.cloudinit_password == null && var.ssh_public_key_path == null ? [] : [1]
      content {
        username = var.cloudinit_username
        password = local.cloudinit_password_hash
        keys     = var.ssh_public_key_path == null ? null : [trimspace(file(var.ssh_public_key_path))]
      }
    }
  }

  network_device {
    bridge       = var.bridge
    model        = var.network_model
    mac_address  = var.management_mac
    vlan_id      = var.management_vlan_id
    enabled      = var.management_nic_enabled
    disconnected = var.management_nic_disconnected
    firewall     = var.management_nic_firewall
    mtu          = var.management_nic_mtu
    queues       = var.management_nic_queues
    rate_limit   = var.management_nic_rate_limit
    trunks       = var.management_nic_trunks
  }

  # Extra NICs are optional and are created in list order. Each NIC may
  # override the shared defaults independently.
  dynamic "network_device" {
    for_each = var.additional_nics
    content {
      bridge       = network_device.value.bridge
      model        = coalesce(network_device.value.model, var.network_model)
      mac_address  = network_device.value.mac_address
      vlan_id      = network_device.value.vlan_id
      enabled      = network_device.value.enabled
      disconnected = network_device.value.disconnected
      firewall     = network_device.value.firewall
      mtu          = network_device.value.mtu
      queues       = network_device.value.queues
      rate_limit   = network_device.value.rate_limit
      trunks       = network_device.value.trunks
    }
  }

  lifecycle {
    # bcrypt uses a random salt. The password is consumed only during the
    # one-time bootstrap, so ignore the newly generated hash after creation.
    # Recreate the VM to apply a changed bootstrap password.
    ignore_changes = [initialization[0].user_account[0].password]

    precondition {
      condition = (
        var.image_source != "local" ||
        (var.image_path != null && try(fileexists(var.image_path), false))
      )
      error_message = "image_source=local requires image_path to reference an existing local image file."
    }

    precondition {
      condition = (
        var.image_source != "proxmox" ||
        (var.image_file_id != null && can(regex("^[^:]+:import/.+$", var.image_file_id)))
      )
      error_message = "image_source=proxmox requires image_file_id in the form <datastore>:import/<file-name>."
    }
  }

  operating_system {
    type = var.operating_system_type
  }

  dynamic "serial_device" {
    for_each = var.serial_device_enabled ? [1] : []
    content {
      device = var.serial_device
    }
  }
}

# The bpg/proxmox resource exposes guest IP addresses but currently drops the
# prefix returned by QEMU Guest Agent. Read the raw API response so the netmask
# remains correct for preserve, DHCP and static modes.
data "external" "management_network" {
  count = var.vm_started && var.qemu_agent_enabled ? 1 : 0

  program = ["python3", "${path.module}/scripts/read-management-network.py"]

  query = {
    endpoint       = var.proxmox_endpoint
    insecure       = tostring(var.proxmox_insecure)
    node_name      = var.node_name
    vm_id          = tostring(proxmox_virtual_environment_vm.opnsense.vm_id)
    management_mac = proxmox_virtual_environment_vm.opnsense.network_device[0].mac_address
    token_file     = "${path.module}/token.auto.tfvars"
  }

  depends_on = [proxmox_virtual_environment_vm.opnsense]
}
