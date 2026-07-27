# The ID may have been explicitly requested or automatically assigned by Proxmox.
output "vm_id" {
  description = "Actual Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.opnsense.vm_id
}

output "management_ip" {
  description = "Actual IPv4 address of the management interface reported by QEMU Guest Agent."
  value = (
    try(data.external.management_network[0].result.management_ip, "") == "" ?
    null : data.external.management_network[0].result.management_ip
  )
}

output "management_netmask" {
  description = "Actual dotted-decimal netmask of the management interface reported by QEMU Guest Agent."
  value = (
    try(data.external.management_network[0].result.management_netmask, "") == "" ?
    null : data.external.management_network[0].result.management_netmask
  )
}

output "source_image_file_id" {
  description = "Proxmox import file ID used as the source of the VM system disk."
  value       = local.source_image_file_id
}
