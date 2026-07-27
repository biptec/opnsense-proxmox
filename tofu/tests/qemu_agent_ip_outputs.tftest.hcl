mock_provider "proxmox" {}

run "outputs_use_guest_agent_addresses" {
  command = apply

  variables {
    proxmox_endpoint   = "https://proxmox.example.invalid:8006/"
    proxmox_api_token  = "test@pve!token=test-secret"
    node_name          = "node1"
    vm_datastore       = "local-lvm"
    management_address = "192.0.2.10/24"

    image_source  = "proxmox"
    image_file_id = "local:import/OPNsense.qcow2"
    vm_started    = false
  }

  override_resource {
    target = proxmox_virtual_environment_vm.opnsense
    values = {
      ipv4_addresses = [
        ["127.0.0.1"],
        ["169.254.10.20", "10.200.0.77/24"],
        ["198.51.100.8"],
      ]
      ipv6_addresses = [
        ["::1"],
        ["fe80::1234", "2001:db8::77/64"],
      ]
      network_interface_names = ["lo0", "vtnet0", "vtnet1"]
      vm_id                  = 104
    }
  }

  assert {
    condition     = output.management_ip == "10.200.0.77"
    error_message = "management_ip must contain the IP portion reported by QEMU Guest Agent."
  }

  assert {
    condition     = output.management_cidr == "10.200.0.77/24"
    error_message = "management_cidr must preserve the guest-reported prefix."
  }

  assert {
    condition     = output.management_prefix_length == 24
    error_message = "management_prefix_length must expose the prefix without requiring CIDR parsing."
  }

  assert {
    condition     = output.management_netmask == "255.255.255.0"
    error_message = "management_netmask must expose the dotted-decimal IPv4 netmask."
  }

  assert {
    condition = jsonencode(output.ipv4_addresses) == jsonencode([
      {
        interface     = "vtnet0"
        address       = "10.200.0.77"
        cidr          = "10.200.0.77/24"
        prefix_length = 24
        netmask       = "255.255.255.0"
      },
      {
        interface     = "vtnet1"
        address       = "198.51.100.8"
        cidr          = "198.51.100.8/32"
        prefix_length = 32
        netmask       = "255.255.255.255"
      },
    ])
    error_message = "IPv4 outputs must preserve interface and network information for each usable address."
  }

  assert {
    condition = jsonencode(output.ipv6_addresses) == jsonencode([
      {
        interface     = "vtnet0"
        address       = "2001:db8::77"
        cidr          = "2001:db8::77/64"
        prefix_length = 64
      },
    ])
    error_message = "IPv6 outputs must preserve interface, CIDR and prefix length."
  }

  assert {
    condition     = output.configured_management_ip == "192.0.2.10"
    error_message = "configured_management_ip must preserve the requested Cloud-Init address separately."
  }
}
