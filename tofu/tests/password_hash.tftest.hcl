mock_provider "proxmox" {}

run "password_is_prehashed" {
  command = apply

  variables {
    proxmox_endpoint  = "https://proxmox.example.invalid:8006/"
    proxmox_api_token = "test@pve!token=test-secret"
    node_name         = "node1"
    vm_datastore      = "local-lvm"

    image_source       = "proxmox"
    image_file_id      = "local:import/OPNsense.qcow2"
    cloudinit_password = "test-password"
    vm_started         = false
  }

  assert {
    condition = startswith(
      nonsensitive(local.cloudinit_password_hash),
      "$2a$",
    )
    error_message = "The Cloud-Init password must be converted to a bcrypt $2a$ crypt hash."
  }

  assert {
    condition = length(
      nonsensitive(local.cloudinit_password_hash),
    ) == 60
    error_message = "The bcrypt crypt hash must be 60 characters long."
  }

  assert {
    condition     = nonsensitive(local.cloudinit_password_hash) != "test-password"
    error_message = "The provider must not receive the plaintext bootstrap password."
  }
}
