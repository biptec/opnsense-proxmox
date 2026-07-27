mock_provider "proxmox" {}
mock_provider "external" {}

run "outputs_use_raw_guest_agent_network_data" {
  command = apply

  variables {
    proxmox_endpoint  = "https://proxmox.example.invalid:8006/"
    proxmox_api_token = "test@pve!token=test-secret"
    node_name         = "node1"
    vm_datastore      = "local-lvm"
    vm_id             = 104
    management_mac    = "02:00:00:00:00:01"

    image_source  = "proxmox"
    image_file_id = "local:import/OPNsense.qcow2"
    vm_started    = true
  }

  override_data {
    target = data.external.management_network
    values = {
      result = {
        management_ip      = "10.200.0.77"
        management_netmask = "255.255.255.0"
      }
    }
  }

  assert {
    condition     = output.management_ip == "10.200.0.77"
    error_message = "management_ip must be the actual management-interface address reported by QEMU Guest Agent."
  }

  assert {
    condition     = output.management_netmask == "255.255.255.0"
    error_message = "management_netmask must preserve the prefix returned by QEMU Guest Agent."
  }
}
