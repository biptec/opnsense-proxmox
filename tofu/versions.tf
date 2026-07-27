terraform {
  # The configuration uses current OpenTofu language features and provider 0.111.1.
  required_version = ">= 1.12.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }

    external = {
      source  = "hashicorp/external"
      version = "2.4.0"
    }
  }
}

provider "proxmox" {
  # Authentication is intentionally supplied separately from terraform.tfvars.
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}
