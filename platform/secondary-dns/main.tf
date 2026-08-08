locals {
  cloudinit_datastore = coalesce(var.cloudinit_datastore, var.vm_datastore)
  public_transport    = var.primary_router.routed_public_networks["public_transport"]
  trunk_vlans         = join(";", [var.dns_internal.vlan_id, var.ntp_internal.vlan_id, local.public_transport.vlan_id])
}

resource "terraform_data" "contract" {
  input = {
    management   = var.management
    dns_internal = var.dns_internal
    ntp_internal = var.ntp_internal
    public       = var.public
    image_sha256 = var.image.sha256
  }

  lifecycle {
    precondition {
      condition = length(toset([
        var.management.vlan_id,
        var.dns_internal.vlan_id,
        var.ntp_internal.vlan_id,
        local.public_transport.vlan_id,
      ])) == 4
      error_message = "Rigi management, DNS, NTP, and public VLAN IDs must be unique."
    }

    precondition {
      condition     = lower(var.management_mac) != lower(var.trunk_mac)
      error_message = "Rigi management and trunk MAC addresses must be different."
    }

    precondition {
      condition = (
        contains(keys(var.primary_router.routed_interfaces), "public_transport") &&
        contains(keys(var.primary_router.routed_public_networks), "public_transport") &&
        cidrsubnet(var.public.ipv4_cidr, 0, 0) == local.public_transport.subnet &&
        local.public_transport.ipv6_subnet != null &&
        local.public_transport.router_ipv6_address != null &&
        cidrsubnet(var.public.ipv6_cidr, 0, 0) == local.public_transport.ipv6_subnet
      )
      error_message = "Rigi requires the primary-router public_transport interface/network, and both public identities must belong to the exact shared IPv4/IPv6 subnets."
    }


    precondition {
      condition = alltrue([
        cidrcontains(var.management.ipv4_cidr, var.management.ipv4_gateway),
        cidrcontains(var.management.ipv6_cidr, var.management.ipv6_gateway),
        cidrcontains(var.dns_internal.ipv4_cidr, var.dns_internal.ipv4_gateway),
        cidrcontains(var.dns_internal.ipv6_cidr, var.dns_internal.ipv6_gateway),
        cidrcontains(var.ntp_internal.ipv4_cidr, var.ntp_internal.ipv4_gateway),
        cidrcontains(var.ntp_internal.ipv6_cidr, var.ntp_internal.ipv6_gateway),
        cidrcontains(var.public.ipv4_cidr, local.public_transport.router_address),
        try(cidrcontains(var.public.ipv6_cidr, local.public_transport.router_ipv6_address), false),
      ])
      error_message = "Every Rigi gateway must be on-link for its configured service identity."
    }

    precondition {
      condition = (
        length(local.internal_ipv4_networks) > 0 &&
        length(local.internal_ipv6_networks) > 0 &&
        alltrue([for network in var.primary_router.trusted_internal_networks : can(cidrhost(network, 0))])
      )
      error_message = "Rigi requires valid trusted internal CIDRs with at least one IPv4 and one IPv6 scope from the primary-router state."
    }

    precondition {
      condition     = var.primary_router.dns_active_service == "bind"
      error_message = "Rigi integration requires the primary-router state to report BIND as the active DNS service."
    }
  }
}

resource "proxmox_download_file" "image" {
  content_type        = "import"
  datastore_id        = var.image_datastore
  node_name           = var.node_name
  url                 = var.image.url
  file_name           = var.image.filename
  checksum            = var.image.sha256
  checksum_algorithm  = "sha256"
  overwrite           = false
  overwrite_unmanaged = false

  depends_on = [terraform_data.contract]
}

resource "proxmox_virtual_environment_file" "network_data" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore
  node_name    = var.node_name
  overwrite    = true

  source_raw {
    data      = local.network_data
    file_name = "rigi-network-data.yaml"
  }
}

resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore
  node_name    = var.node_name
  overwrite    = true

  source_raw {
    data      = sensitive(local.user_data)
    file_name = "rigi-user-data.yaml"
  }
}

resource "terraform_data" "config_revision" {
  triggers_replace = [
    sha256(local.network_data),
    sha256(local.user_data),
    var.image.sha256,
  ]
}

resource "proxmox_virtual_environment_vm" "rigi" {
  name        = var.vm.name
  description = "Secondary DNS and internal NTP"
  tags        = ["dns", "ntp", "infrastructure"]

  node_name = var.node_name
  vm_id     = var.vm_id
  started   = var.vm.started
  on_boot   = var.vm.on_boot

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  agent {
    enabled = true
    trim    = true
  }

  cpu {
    cores = var.vm.cores
    type  = "host"
  }

  memory {
    dedicated = var.vm.memory_mb
  }

  disk {
    datastore_id = var.vm_datastore
    import_from  = proxmox_download_file.image.id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    ssd          = true
    size         = var.vm.disk_gb
  }

  initialization {
    datastore_id         = local.cloudinit_datastore
    type                 = "nocloud"
    network_data_file_id = proxmox_virtual_environment_file.network_data.id
    user_data_file_id    = proxmox_virtual_environment_file.user_data.id
  }

  # Proxmox access VLAN: Rigi sees management untagged.
  network_device {
    model       = "virtio"
    bridge      = var.bridge
    mac_address = var.management_mac
    vlan_id     = var.management.vlan_id
  }

  # Rigi sees only the approved service/public VLANs tagged.
  network_device {
    model       = "virtio"
    bridge      = var.bridge
    mac_address = var.trunk_mac
    trunks      = local.trunk_vlans
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    replace_triggered_by = [terraform_data.config_revision]
  }

  depends_on = [
    opnsense_firewall_filter.rigi,
    opnsense_firewall_filter.rigi_ipv6,
  ]
}
