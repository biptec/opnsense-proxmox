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
- optionally wait for the first-boot bootstrap and verify the OPNsense API.

## Requirements

- OpenTofu 1.12 or newer;
- Proxmox VE API access;
- `bpg/proxmox` provider 0.111.1;
- an OPNsense image containing the NoCloud bootstrap integration;
- `ssh`, `curl` and Python 3 when `wait_for_api = true`.

## Repository files

```text
main.tf                    VM, image import and optional readiness check
variables.tf               Inputs, defaults, validation and descriptions
outputs.tf                 VM ID, management IP and source image ID
versions.tf                OpenTofu and provider requirements
terraform.tfvars.example   Non-secret configuration example
token.auto.tfvars.example  API token example
scripts/wait-for-api.sh    Optional SSH and API readiness verification
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

## System disk size

The provider otherwise defaults to an 8 GiB disk during creation. The supplied OPNsense image uses a 20 GiB virtual disk, so the configuration defaults to:

```hcl
disk_size_gb = 20
```

The value may be increased but must not be smaller than the virtual size of the source image. Proxmox does not support shrinking disks during import.

## Optional API readiness check

Set `wait_for_api = true` and provide matching SSH key paths to:

1. wait for SSH after first boot;
2. read `/conf/bootstrap-api.json` without printing its contents;
3. perform an authenticated OPNsense API request;
4. save the credentials locally with mode `0600`.

The check is disabled by default.

## Sensitive and local files

Do not commit:

- API tokens;
- `terraform.tfvars`;
- OpenTofu state;
- private SSH keys;
- `bootstrap-api.json`;
- QCOW2 or raw image files.

The provided `.gitignore` excludes these files. State can still contain sensitive resource data, so store it in an appropriately protected backend.

## Important defaults

- `vm_id = null`: Proxmox allocates the next free ID;
- `management_mac = null`: Proxmox generates a MAC address;
- `cloudinit_datastore = null`: `vm_datastore` is used;
- `disk_size_gb = 20`;
- `wait_for_api = false`;
- one VirtIO management NIC is created; extra NICs are optional.

Review `terraform.tfvars.example` and every variable description before applying the configuration to a new environment.
