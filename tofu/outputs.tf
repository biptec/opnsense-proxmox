# The ID may have been explicitly requested or automatically assigned by Proxmox.
output "vm_id" {
  description = "Actual Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.opnsense.vm_id
}

output "management_ip" {
  description = "Management IPv4 address without the CIDR prefix."
  value       = local.management_ip
}

output "source_image_file_id" {
  description = "Proxmox import file ID used as the source of the VM system disk."
  value       = local.source_image_file_id
}
