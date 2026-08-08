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


mock_provider "opnsense" {
  mock_resource "opnsense_interfaces_vlan" {
    defaults = { id = "11111111-1111-4111-8111-111111111111" }
  }
  mock_resource "opnsense_interfaces_assignment" {
    defaults = { id = "opt20", name = "opt20" }
  }
  mock_resource "opnsense_bind_tsig_key" {
    defaults = { id = "22222222-2222-4222-8222-222222222222" }
  }
  mock_resource "opnsense_bind_primary_domain_transfer" {
    defaults = { id = "33333333-3333-4333-8333-333333333333" }
  }
  mock_resource "opnsense_bind_record" {
    defaults = { id = "44444444-4444-4444-8444-444444444444" }
  }
  mock_resource "opnsense_firewall_alias" {
    defaults = { id = "55555555-5555-4555-8555-555555555555" }
  }
  mock_resource "opnsense_firewall_filter" {
    defaults = { id = "66666666-6666-4666-8666-666666666666" }
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

  primary_router = {
    trunk_parent_device       = "vtnet1"
    wan_interface             = "opt1"
    public_interface          = "opt2"
    internal_zone_id          = "77777777-7777-4777-8777-777777777777"
    public_zone_id            = "88888888-8888-4888-8888-888888888888"
    zone_name                 = "biptec.net"
    trusted_internal_networks = ["10.0.0.0/8", "2001:db8::/32"]
    internal_dns_ipv4         = "10.16.16.53"
    public_dns_ipv4           = "198.51.100.88"
    dns_active_service        = "bind"
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
      length(opnsense_interfaces_vlan.rigi) == 3 &&
      opnsense_interfaces_vlan.rigi["management"].tag == 508 &&
      opnsense_interfaces_vlan.rigi["dns"].tag == 2804 &&
      opnsense_interfaces_vlan.rigi["ntp"].tag == 2820
    )
    error_message = "The secondary state must own only its Etna-side VLANs; shared VLAN 3802 is referenced, not created."
  }

  assert {
    condition = (
      opnsense_bind_primary_domain_transfer.internal.domain_id == "77777777-7777-4777-8777-777777777777" &&
      opnsense_bind_primary_domain_transfer.internal.also_notify == toset(["10.16.18.53"]) &&
      opnsense_bind_primary_domain_transfer.public.domain_id == "88888888-8888-4888-8888-888888888888" &&
      opnsense_bind_primary_domain_transfer.public.also_notify == toset(["5.9.227.114"])
    )
    error_message = "Rigi must own additive transfer attachments without owning either primary zone."
  }

  assert {
    condition = (
      opnsense_bind_record.internal_ns2.value == "ns2.biptec.net." &&
      opnsense_bind_record.internal_ns2_ipv4.value == "10.16.18.53" &&
      opnsense_bind_record.public_ns2.value == "ns2.biptec.net." &&
      opnsense_bind_record.public_ns2_ipv4.value == "5.9.227.114" &&
      opnsense_firewall_alias.rigi_internal_ipv4.content == toset(["10.0.0.0/8"]) &&
      opnsense_firewall_alias.rigi_internal_ipv6.content == toset(["2001:db8::/32"]) &&
      opnsense_firewall_filter.rigi["management_ssh"].interface.invert &&
      opnsense_firewall_filter.rigi["management_ssh"].interface.interface == toset(["opt1"]) &&
      opnsense_firewall_filter.rigi["internal_dns_tcp"].interface.invert &&
      opnsense_firewall_filter.rigi_ipv6["internal_ntp"].interface.invert &&
      opnsense_firewall_filter.rigi_ipv6["internal_ntp"].interface.interface == toset(["opt1"])
    )
    error_message = "Rigi state must own its NS2 and trusted-client firewall integration on every Etna ingress except WAN."
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

run "reject_secondary_before_primary_bind_cutover" {
  command = plan

  variables {
    primary_router = {
      trunk_parent_device       = "vtnet1"
      wan_interface             = "opt1"
      public_interface          = "opt2"
      internal_zone_id          = "77777777-7777-4777-8777-777777777777"
      public_zone_id            = "88888888-8888-4888-8888-888888888888"
      zone_name                 = "biptec.net"
      trusted_internal_networks = ["10.0.0.0/8", "2001:db8::/32"]
      internal_dns_ipv4         = "10.16.16.53"
      public_dns_ipv4           = "198.51.100.88"
      dns_active_service        = "unbound"
    }
  }

  expect_failures = [terraform_data.contract]
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
