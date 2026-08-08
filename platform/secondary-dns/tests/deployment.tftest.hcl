mock_provider "proxmox" {
  mock_resource "proxmox_download_file" {
    defaults = { id = "local:import/ubuntu-24.04-server-cloudimg-amd64-20260705.qcow2" }
  }
  mock_resource "proxmox_virtual_environment_file" {
    defaults = { id = "local:snippets/rigi-data.yaml" }
  }
  mock_resource "proxmox_virtual_environment_vm" {
    defaults = { vm_id = 508 }
  }
}

variables {
  proxmox_endpoint  = "https://127.0.0.1:8006"
  proxmox_api_token = "test@pam!test=test"
  node_name         = "tofana"
  vm_datastore      = "vm-storage"

  management = {
    vlan_id      = 508
    ipv4_cidr    = "10.16.222.2/30"
    ipv4_gateway = "10.16.222.1"
    ipv6_cidr    = "2a07:e580:a10:de00::2/64"
    ipv6_gateway = "2a07:e580:a10:de00::1"
  }

  dns_internal = {
    vlan_id      = 2804
    ipv4_cidr    = "10.16.18.53/30"
    ipv4_gateway = "10.16.18.54"
    ipv6_cidr    = "2a07:e580:a10:1234::2/64"
    ipv6_gateway = "2a07:e580:a10:1234::1"
  }

  ntp_internal = {
    vlan_id      = 2820
    ipv4_cidr    = "10.16.18.122/30"
    ipv4_gateway = "10.16.18.121"
    ipv6_cidr    = "2a07:e580:a10:1278::2/64"
    ipv6_gateway = "2a07:e580:a10:1278::1"
  }

  public = {
    vlan_id      = 3802
    ipv4_cidr    = "5.9.227.114/29"
    ipv4_gateway = "5.9.227.113"
  }

  primary = {
    zone_name            = "biptec.net"
    internal_dns_ipv4    = "10.16.16.53"
    internal_notify_ipv4 = "10.16.18.54"
    public_dns_ipv4      = "138.201.128.88"
    public_notify_ipv4   = "5.9.227.113"
  }

  transfer_tsig_secret = "/////w=="
}

run "rigi_immutable_composition" {
  command = plan

  assert {
    condition = (
      proxmox_download_file.image.checksum_algorithm == "sha256" &&
      proxmox_download_file.image.checksum == "ffe6203da54deeb6db5d2a98a83f9ec8e55f149d3f7ba622e1abe5fa966ee3d6"
    )
    error_message = "Rigi must use the pinned Ubuntu 24.04 image checksum."
  }

  assert {
    condition = (
      proxmox_virtual_environment_vm.rigi.network_device[0].bridge == "vmbr1" &&
      proxmox_virtual_environment_vm.rigi.network_device[0].vlan_id == 508 &&
      proxmox_virtual_environment_vm.rigi.network_device[1].bridge == "vmbr1" &&
      proxmox_virtual_environment_vm.rigi.network_device[1].trunks == "2804;2820;3802"
    )
    error_message = "Rigi management must be access VLAN 508 while its second NIC carries only the approved tagged VLANs."
  }

  assert {
    condition = (
      proxmox_virtual_environment_vm.rigi.initialization[0].network_data_file_id == proxmox_virtual_environment_file.network_data.id &&
      proxmox_virtual_environment_vm.rigi.initialization[0].user_data_file_id == proxmox_virtual_environment_file.user_data.id
    )
    error_message = "Rigi must be configured entirely by Terraform-owned cloud-init network and user data."
  }

  assert {
    condition = (
      output.management_address == "10.16.222.2" &&
      output.internal_dns_address == "10.16.18.53" &&
      output.internal_ntp_address == "10.16.18.122" &&
      output.public_dns_address == "5.9.227.114"
    )
    error_message = "Rigi outputs must preserve the approved service identities."
  }
}

run "reject_duplicate_rigi_vlan" {
  command = plan

  variables {
    ntp_internal = {
      vlan_id      = 2804
      ipv4_cidr    = "10.16.18.122/30"
      ipv4_gateway = "10.16.18.121"
      ipv6_cidr    = "2a07:e580:a10:1278::2/64"
      ipv6_gateway = "2a07:e580:a10:1278::1"
    }
  }

  expect_failures = [terraform_data.contract]
}

run "reject_offlink_public_gateway" {
  command = plan

  variables {
    public = {
      vlan_id      = 3802
      ipv4_cidr    = "5.9.227.114/29"
      ipv4_gateway = "5.9.227.121"
    }
  }

  expect_failures = [terraform_data.contract]
}
