locals {
  # Keep repeated and mode-dependent values in one place.
  management_ip          = split("/", var.management_address)[0]
  cloudinit_datastore_id = coalesce(var.cloudinit_datastore, var.vm_datastore)

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

  machine       = var.vm_machine
  scsi_hardware = var.vm_scsi_hardware
  boot_order    = var.vm_boot_order

  agent {
    enabled = var.qemu_agent_enabled
    timeout = var.qemu_agent_timeout
    trim    = var.qemu_agent_trim
    type    = var.qemu_agent_type
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
  }

  # Proxmox generates a NoCloud drive. The custom OPNsense bootstrap reads it
  # on first boot and applies hostname, network, DNS, SSH keys, and API setup.
  initialization {
    datastore_id = local.cloudinit_datastore_id

    dynamic "dns" {
      for_each = var.dns_domain == null && length(var.dns_servers) == 0 ? [] : [1]
      content {
        domain  = var.dns_domain
        servers = var.dns_servers
      }
    }

    ip_config {
      ipv4 {
        address = var.management_address
        gateway = var.management_gateway
      }
    }

    dynamic "user_account" {
      for_each = var.ssh_public_key_path == null ? [] : [var.ssh_public_key_path]
      content {
        username = var.cloudinit_username
        keys     = [trimspace(file(user_account.value))]
      }
    }
  }

  network_device {
    bridge       = var.bridge
    model        = var.network_model
    mac_address  = var.management_mac
    vlan_id      = var.management_vlan_id
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
      disconnected = network_device.value.disconnected
      firewall     = network_device.value.firewall
      mtu          = network_device.value.mtu
      queues       = network_device.value.queues
      rate_limit   = network_device.value.rate_limit
      trunks       = network_device.value.trunks
    }
  }

  lifecycle {
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

# Optional post-deployment verification. This is a separate resource: the VM
# can already be running while this step waits for SSH credentials and the API.
resource "terraform_data" "wait_for_api" {
  count      = var.wait_for_api ? 1 : 0
  depends_on = [proxmox_virtual_environment_vm.opnsense]

  triggers_replace = [
    proxmox_virtual_environment_vm.opnsense.id,
    var.management_address,
    try(filesha256(var.ssh_private_key_path), null),
  ]

  lifecycle {
    precondition {
      condition = (
        var.ssh_public_key_path != null &&
        var.ssh_private_key_path != null &&
        try(fileexists(var.ssh_public_key_path), false) &&
        try(fileexists(var.ssh_private_key_path), false)
      )
      error_message = "wait_for_api requires existing ssh_public_key_path and ssh_private_key_path files."
    }
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/wait-for-api.sh"

    environment = {
      SSH_HOST              = local.management_ip
      SSH_USER              = var.cloudinit_username
      SSH_KEY               = var.ssh_private_key_path
      SSH_WAIT_ATTEMPTS     = tostring(var.ssh_wait_attempts)
      API_WAIT_ATTEMPTS     = tostring(var.api_wait_attempts)
      WAIT_INTERVAL_SECONDS = tostring(var.wait_interval_seconds)
      API_SCHEME            = var.api_scheme
      API_ENDPOINT_PATH     = var.api_endpoint_path
      API_CREDENTIALS_OUT   = var.api_credentials_path
    }
  }
}
