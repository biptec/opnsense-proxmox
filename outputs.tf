# The ID may have been explicitly requested or automatically assigned by Proxmox.
output "vm_id" {
  description = "Actual Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.firewall.vm_id
}

output "management_ip" {
  description = "Management IPv4 address without the CIDR prefix."
  value       = local.management_ip
}

output "api_credentials_path" {
  description = "Credentials file created by the optional API readiness check; null when that check is disabled."
  value       = var.wait_for_api ? var.api_credentials_path : null
}

output "source_image_file_id" {
  description = "Proxmox import file ID used as the source of the VM system disk."
  value       = local.source_image_file_id
}
