mock_provider "proxmox" {}
mock_provider "external" {}

run "preserve_omits_nocloud_ip_config" {
  command = plan

  variables {
    proxmox_endpoint  = "https://proxmox.example.invalid:8006/"
    proxmox_api_token = "test@pve!token=test-secret"
    node_name         = "node1"
    vm_datastore      = "local-lvm"
    image_source      = "proxmox"
    image_file_id     = "local:import/OPNsense.qcow2"
    vm_started        = false
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.opnsense.initialization[0].ip_config) == 0
    error_message = "preserve mode must omit NoCloud IP configuration."
  }
}

run "dhcp_requests_dhcp" {
  command = plan

  variables {
    proxmox_endpoint  = "https://proxmox.example.invalid:8006/"
    proxmox_api_token = "test@pve!token=test-secret"
    node_name         = "node1"
    vm_datastore      = "local-lvm"
    image_source      = "proxmox"
    image_file_id     = "local:import/OPNsense.qcow2"
    vm_started        = false
    management_ipv4   = { mode = "dhcp" }
  }

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.initialization[0].ip_config[0].ipv4[0].address == "dhcp"
    error_message = "dhcp mode must request DHCP from Proxmox NoCloud."
  }
}

run "static_applies_address_and_gateway" {
  command = plan

  variables {
    proxmox_endpoint  = "https://proxmox.example.invalid:8006/"
    proxmox_api_token = "test@pve!token=test-secret"
    node_name         = "node1"
    vm_datastore      = "local-lvm"
    image_source      = "proxmox"
    image_file_id     = "local:import/OPNsense.qcow2"
    vm_started        = false
    management_ipv4 = {
      mode    = "static"
      address = "10.200.0.50/24"
      gateway = "10.200.0.1"
    }
  }

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.initialization[0].ip_config[0].ipv4[0].address == "10.200.0.50/24"
    error_message = "static mode must pass the configured CIDR to NoCloud."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.initialization[0].ip_config[0].ipv4[0].gateway == "10.200.0.1"
    error_message = "static mode must pass the configured gateway to NoCloud."
  }
}

run "static_requires_address" {
  command = plan

  variables {
    proxmox_endpoint  = "https://proxmox.example.invalid:8006/"
    proxmox_api_token = "test@pve!token=test-secret"
    node_name         = "node1"
    vm_datastore      = "local-lvm"
    image_source      = "proxmox"
    image_file_id     = "local:import/OPNsense.qcow2"
    vm_started        = false
    management_ipv4   = { mode = "static" }
  }

  expect_failures = [var.management_ipv4]
}
