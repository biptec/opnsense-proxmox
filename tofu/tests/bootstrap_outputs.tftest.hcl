mock_provider "proxmox" {}
mock_provider "external" {}

run "bootstrap_identity_outputs" {
  command = plan

  variables {
    proxmox_endpoint   = "https://proxmox.example.invalid:8006/"
    proxmox_api_token  = "test@pve!token=test-secret"
    node_name          = "node1"
    vm_datastore       = "local-lvm"
    image_source       = "proxmox"
    image_file_id      = "local:import/OPNsense.qcow2"
    vm_started         = false
    vm_name            = "router1"
    dns_domain         = "biptec.net"
    cloudinit_username = "sysops"
  }

  assert {
    condition     = output.cloudinit_username == "sysops"
    error_message = "cloudinit_username output must match the SSH bootstrap account."
  }

  assert {
    condition     = output.management_fqdn == "router1.biptec.net"
    error_message = "management_fqdn must combine vm_name and dns_domain."
  }
}
