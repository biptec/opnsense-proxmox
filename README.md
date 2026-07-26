# OPNsense on Proxmox

OpenTofu configuration for deploying and bootstrapping OPNsense virtual machines on Proxmox VE.

The project keeps environment-specific settings outside the base image and supports reproducible deployment through the Proxmox API and NoCloud data.

## Features

- upload a local QCOW2 or raw image to Proxmox;
- use an image already stored in Proxmox as content type `import`;
- import the source image into the selected VM storage;
- let Proxmox allocate the VM ID and management MAC automatically;
- configure CPU, memory, system disk, bridge, VLAN and additional NICs;
- pass hostname, management IP, gateway, DNS and SSH keys through NoCloud;

## Requirements

- OpenTofu 1.12 or newer;
- Proxmox VE API access;
- `bpg/proxmox` provider 0.111.1;
- an OPNsense image containing the NoCloud bootstrap integration.

## Repository files

```text
main.tf                    VM and image import configuration
variables.tf               Inputs, defaults, validation and descriptions
outputs.tf                 VM ID, management IP and source image ID
versions.tf                OpenTofu and provider requirements
terraform.tfvars.example   Non-secret configuration example
token.auto.tfvars.example  API token example
```

## Quick start

Copy the examples and add local values:

```sh
cp terraform.tfvars.example terraform.tfvars
cp token.auto.tfvars.example token.auto.tfvars
```

Keep the API token outside `terraform.tfvars`:

```hcl
proxmox_api_token = "user@realm!token-id=token-secret"
```

Then initialise and review the deployment:

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan
tofu apply
```

## Image source modes

### Upload a local image

```hcl
image_source    = "local"
image_datastore = "local"
image_path      = "./OPNsense.qcow2"
image_sha256    = "optional-sha256"
```

OpenTofu uploads the file as content type `import`, then creates the VM disk on `vm_datastore`.

### Use an existing Proxmox image

```hcl
image_source  = "proxmox"
image_file_id = "local:import/OPNsense.qcow2"
```

The existing import file remains outside OpenTofu management and is not deleted by this configuration.

## Configurable VM hardware

All VM values explicitly managed by this configuration are exposed as variables rather than fixed literals in `main.tf`. This includes:

- VM description, tags, power state, boot behaviour, BIOS, machine type, protection, pool, hotplug and lifecycle settings;
- QEMU guest agent settings, including optional IP waiting;
- CPU type, sockets, cores, flags, NUMA, affinity, limits and units;
- dedicated, balloon, hugepage and shared-memory settings;
- system-disk interface, size, cache, discard, I/O thread, queues, replication, SSD flag and optional I/O limits;
- Cloud-Init datastore, interface, type, upgrade policy and username;
- management and additional NIC model, VLAN, firewall, MTU, queues, rate limit and trunk settings;
- guest OS type and serial console device.

Defaults are declared in `variables.tf`. Override only the required values in `terraform.tfvars`; see `terraform.tfvars.example` for common examples.

## System disk size

The provider otherwise defaults to an 8 GiB disk during creation. The current OPNsense image has a virtual size of approximately `20.254 GiB`, so the smallest whole-GiB value accepted by Proxmox is:

```hcl
disk_size_gb = 21
```

The value may be increased but must not be smaller than the virtual size of the source image. Proxmox does not support shrinking disks during import.


## Resource address migration

The VM resource is named `proxmox_virtual_environment_vm.opnsense`. A `moved` block migrates the previous state address `proxmox_virtual_environment_vm.firewall` without destroying or recreating the VM.

## Post-deployment verification

OpenTofu finishes after Proxmox creates and starts the VM. It does not attempt SSH access or an OPNsense API readiness check. Verify the first boot and bootstrap result manually through the Proxmox console.

A successful `apply` confirms that the requested Proxmox resources were created; it does not prove that every guest service is ready.

## Sensitive and local files

Do not commit:

- API tokens;
- `terraform.tfvars`;
- OpenTofu state;
- private SSH keys;
- QCOW2 or raw image files.

The provided `.gitignore` excludes these files. State can still contain sensitive resource data, so store it in an appropriately protected backend.

## Important defaults

- `vm_id = null`: Proxmox allocates the next free ID;
- `management_mac = null`: Proxmox generates a MAC address;
- `cloudinit_datastore = null`: `vm_datastore` is used;
- `disk_size_gb = 21`;
- one VirtIO management NIC is created; extra NICs are optional.

Review `terraform.tfvars.example` and every variable description before applying the configuration to a new environment.
