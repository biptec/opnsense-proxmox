locals {
  # Keep repeated and mode-dependent values in one place.
  management_ip          = split("/", var.management_address)[0]
  cloudinit_datastore_id = coalesce(var.cloudinit_datastore, var.vm_datastore)

  # Both modes produce the same Proxmox file ID consumed by disk.import_from.
  # local mode gets it from the upload resource; proxmox mode uses the supplied ID.
  source_image_file_id = var.image_source == "local" ? proxmox_virtual_environment_file.image[0].id : var.image_file_id
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

# Create the OPNsense virtual machine from the uploaded image.
resource "proxmox_virtual_environment_vm" "firewall" {
  name        = var.vm_name
  description = "Managed by OpenTofu"
  tags        = ["opnsense", "managed"]

  node_name       = var.node_name
  vm_id           = var.vm_id # null lets Proxmox allocate the next free ID.
  started         = true
  on_boot         = true
  stop_on_destroy = true

  # q35, VirtIO SCSI, and host CPU are appropriate defaults for this image.
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  agent {
    enabled = false
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  # import_from accepts either the file uploaded above or an existing Proxmox
  # import file. On ZFS-backed storage the resulting VM disk is a raw zvol.
  disk {
    datastore_id = var.vm_datastore
    import_from  = local.source_image_file_id
    interface    = "scsi0"

    # The provider otherwise defaults to an 8 GiB disk and would try to shrink
    # the imported 20 GiB image. Proxmox supports growth, but not shrinking.
    size    = var.disk_size_gb
    discard = "on"
    ssd     = true
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
        username = "root"
        keys     = [trimspace(file(user_account.value))]
      }
    }
  }

  # Omitting management_mac delegates MAC allocation to Proxmox.
  network_device {
    bridge      = var.bridge
    model       = "virtio"
    mac_address = var.management_mac
    vlan_id     = var.management_vlan_id
  }

  # Extra NICs are optional and are created in list order.
  dynamic "network_device" {
    for_each = var.additional_nics
    content {
      bridge      = network_device.value.bridge
      model       = "virtio"
      mac_address = try(network_device.value.mac_address, null)
      vlan_id     = try(network_device.value.vlan_id, null)
    }
  }

  lifecycle {
    # Local mode needs an existing file on the machine running OpenTofu.
    precondition {
      condition = (
        var.image_source != "local" ||
        (var.image_path != null && try(fileexists(var.image_path), false))
      )
      error_message = "image_source=local requires image_path to reference an existing local image file."
    }

    # Proxmox mode needs a file already stored as content type import.
    precondition {
      condition = (
        var.image_source != "proxmox" ||
        (var.image_file_id != null && can(regex("^[^:]+:import/.+$", var.image_file_id)))
      )
      error_message = "image_source=proxmox requires image_file_id in the form <datastore>:import/<file-name>."
    }
  }

  operating_system {
    type = "other"
  }

  # A serial console remains useful if network bootstrap fails.
  serial_device {}
}

# Optional post-deployment verification. It is disabled by default so the VM
# can be deployed without local SSH key files or automatic API credential copy.
resource "terraform_data" "wait_for_api" {
  count      = var.wait_for_api ? 1 : 0
  depends_on = [proxmox_virtual_environment_vm.firewall]

  triggers_replace = [
    proxmox_virtual_environment_vm.firewall.id,
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
      SSH_HOST            = local.management_ip
      SSH_KEY             = var.ssh_private_key_path
      API_SCHEME          = var.api_scheme
      API_CREDENTIALS_OUT = var.api_credentials_path
    }
  }
}
