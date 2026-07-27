# OPNsense on Proxmox

OpenTofu configuration for deploying and bootstrapping OPNsense virtual machines on Proxmox VE.

The project keeps environment-specific settings outside the base image and supports reproducible deployment through the Proxmox API and NoCloud data.

## Features

- upload a local QCOW2 or raw image to Proxmox;
- use an image already stored in Proxmox as content type `import`;
- import the source image into the selected VM storage;
- let Proxmox allocate the VM ID and management MAC automatically;
- configure CPU, memory, system disk, bridge, VLAN and additional NICs;
- pass hostname, management IP, gateway, DNS and optional administrative credentials through NoCloud;
- enable QEMU Guest Agent integration for Proxmox by default;

## Requirements

- OpenTofu 1.12 or newer;
- Proxmox VE API access;
- `bpg/proxmox` provider 0.111.1;
- an OPNsense build environment with `/usr/tools` and `/usr/plugins` when producing a new image;
- the guest package in `guest/nocloud-bootstrap`, built together with `os-qemu-guest-agent`.

## Repository files

```text
tofu/                      OpenTofu deployment configuration and examples
  main.tf                  VM and image import configuration
  variables.tf             Inputs, defaults, validation and descriptions
  outputs.tf               VM ID, guest-reported IP addresses and source image ID
  versions.tf              OpenTofu and provider requirements
  terraform.tfvars.example Non-secret configuration example
  token.auto.tfvars.example API token example
guest/nocloud-bootstrap/   Guest-side NoCloud package and tests
image/build.sh             Reproducible Proxmox QCOW2 build entrypoint
```

## Quick start

Copy the examples and add local values:

```sh
cp tofu/terraform.tfvars.example tofu/terraform.tfvars
cp tofu/token.auto.tfvars.example tofu/token.auto.tfvars
```

Keep the API token outside `tofu/terraform.tfvars`:

```hcl
proxmox_api_token = "user@realm!token-id=token-secret"
```

Then initialise and review the deployment:

```sh
tofu -chdir=tofu init
tofu -chdir=tofu fmt -check
tofu -chdir=tofu validate
tofu -chdir=tofu plan
tofu -chdir=tofu apply
```

## Build the OPNsense image

The repository contains both sides of the deployment contract. OpenTofu sends NoCloud data from the Proxmox side, while `os-nocloud-bootstrap` consumes it inside OPNsense.

Build the QCOW2 on the OPNsense build host:

```sh
./image/build.sh
```

The wrapper calls the OPNsense custom-image pipeline with:

```sh
make -C /usr/tools custom-vm,qcow2,20G,never,proxmox \
  ADDITIONS="os-qemu-guest-agent /path/to/opnsense-proxmox/guest/nocloud-bootstrap"
```

The guest package installs:

```text
/usr/local/opnsense/scripts/boot/nocloud_bootstrap.py
/usr/local/etc/rc.syshook.d/early/20-nocloud-bootstrap
```

The source remains in this repository; it is not stored in the OPNsense core fork.

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

All VM values explicitly managed by this configuration are exposed as variables rather than fixed literals in `tofu/main.tf`. This includes:

- VM description, tags, power state, boot behaviour, BIOS, machine type, protection, pool, hotplug and lifecycle settings;
- QEMU guest agent settings, including optional IP waiting;
- CPU type, sockets, cores, flags, NUMA, affinity, limits and units;
- dedicated, balloon, hugepage and shared-memory settings;
- system-disk interface, size, cache, discard, I/O thread, queues, replication, SSD flag and optional I/O limits;
- Cloud-Init datastore, interface, type, upgrade policy and username;
- management and additional NIC model, VLAN, firewall, MTU, queues, rate limit and trunk settings;
- guest OS type and serial console device.

Defaults are declared in `tofu/variables.tf`. Override only the required values in `tofu/terraform.tfvars`; see `tofu/terraform.tfvars.example` for common examples.

## System disk size

The provider otherwise defaults to an 8 GiB disk during creation. The current OPNsense image has a virtual size of approximately `20.254 GiB`, so the smallest whole-GiB value accepted by Proxmox is:

```hcl
disk_size_gb = 21
```

The value may be increased but must not be smaller than the virtual size of the source image. Proxmox does not support shrinking disks during import.


## Resource address migration

The VM resource is named `proxmox_virtual_environment_vm.opnsense`. A `moved` block migrates the previous state address `proxmox_virtual_environment_vm.firewall` without destroying or recreating the VM.

## Administrative access

The NoCloud bootstrap creates `cloudinit_username` only when at least one credential is supplied. The password and SSH key are independent:

| Password | SSH key | Result |
| --- | --- | --- |
| set | omitted | WebUI access; SSH remains disabled |
| omitted | set | key-only SSH access; no password login |
| set | set | WebUI access and key-only SSH access |
| omitted | omitted | no remote administrative account is created |

The created user belongs to the OPNsense `admins` group and receives administrative `sudo` access. Root is disabled in OPNsense local authentication, preventing root login to WebUI and API. The operating-system root account remains available through the trusted Proxmox console for recovery.

SSH is enabled only when `ssh_public_key_path` is set. Root SSH login and SSH password authentication remain disabled. The username is configurable and is not embedded in the image.

`cloudinit_password` is sensitive and should be supplied through a gitignored `*.auto.tfvars` file or the `TF_VAR_cloudinit_password` environment variable. OpenTofu converts the plaintext to a bcrypt crypt hash before sending it to Proxmox, so the generated NoCloud data uses a format supported by OPNsense instead of depending on the Proxmox host's default hashing algorithm. Protect tfvars and saved plan files because they can contain the plaintext input.

The bootstrap is intentionally one-time. Changing `cloudinit_password` on an existing VM does not rotate the OPNsense password; recreate the VM to apply a different bootstrap password. The VM lifecycle ignores later password-hash differences because `bcrypt()` uses a new random salt on each evaluation.

## QEMU Guest Agent

QEMU Guest Agent is enabled in both layers: the OPNsense image starts the agent, and the Proxmox VM configuration exposes the `virtio` guest-agent channel. By default, OpenTofu waits for the guest to report an IPv4 address before completing `apply`. Set `qemu_agent_wait_for_ip.disabled = true` to opt out.

The IP outputs describe actual guest state reported through Proxmox rather than repeating Cloud-Init input:

- `management_ip`: IP portion of the first usable guest-reported IPv4 address;
- `management_cidr`: the same address with its prefix;
- `management_prefix_length`: numeric prefix length;
- `management_netmask`: dotted-decimal IPv4 netmask;
- `ipv4_addresses`: all usable IPv4 addresses as objects containing `interface`, `address`, `cidr`, `prefix_length` and `netmask`;
- `ipv6_addresses`: all usable IPv6 addresses as objects containing `interface`, `address`, `cidr` and `prefix_length`;
- `configured_management_ip`: IPv4 address requested through Cloud-Init.

Loopback, link-local and unspecified addresses are excluded. Network information is returned in separate fields, so consumers do not need to parse CIDR strings. This also works when the guest obtains its address through DHCP or retains an address already present in the source image.

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
- `cloudinit_username = "proxmox"`;
- `cloudinit_password = null`: no WebUI password is provisioned;
- `ssh_public_key_path = null`: SSH remains disabled;
- `qemu_agent_enabled = true`;
- QEMU Guest Agent IPv4 waiting is enabled;
- one VirtIO management NIC is created; extra NICs are optional.

Review `tofu/terraform.tfvars.example` and every variable description before applying the configuration to a new environment.
