# OPNsense on Proxmox

OpenTofu configuration for deploying and bootstrapping OPNsense virtual machines on Proxmox VE.

The project keeps environment-specific settings outside the base image and supports reproducible deployment through the Proxmox API and NoCloud data.

## Features

- upload a local QCOW2 or raw image to Proxmox;
- use an image already stored in Proxmox as content type `import`;
- import the source image into the selected VM storage;
- let Proxmox allocate the VM ID and management MAC automatically;
- configure CPU, memory, system disk, bridge, VLAN and additional NICs;
- preserve image networking, request DHCP, or apply a static management IPv4 configuration through NoCloud;
- apply hostname, DNS and optional administrative credentials independently from the network mode;
- enable QEMU Guest Agent integration for Proxmox by default;
- include the OPNsense Caddy plugin for API-managed reverse proxy configuration;
- wait for SSH and run a versioned idempotent post-deployment bootstrap;
- generate an OPNsense API key without storing it in OpenTofu state;
- move the WebUI to a management-only HTTPS port and issue its certificate from an internal CA;
- apply global Caddy settings and direct HTTP/HTTPS firewall ingress on ports 80 and 443;
- provide a reusable Caddy reverse-proxy module for application repositories;
- provide a direct edge-ingress module with no destination NAT or port translation;

## Requirements

- OpenTofu 1.12 or newer;
- Proxmox VE API access, including `VM.GuestAgent.Audit` on the deployed VM;
- `bpg/proxmox` provider 0.111.1;
- `hashicorp/external` provider 2.4.0;
- `biptec/opnsense` provider 0.26.1 for global router settings;
- Python 3, OpenSSH and SCP on the OpenTofu runner;
- an SSH private key matching the NoCloud public key;
- an OPNsense build environment with `/usr/tools` and `/usr/plugins` when producing a new image;
- the local packages in `guest/nocloud-bootstrap` and `guest/caddy-policy`, built together with `os-qemu-guest-agent` and `os-caddy`.

## Repository files

```text
tofu/                       VM lifecycle stage: image, VM, NoCloud and outputs
router/                     Global OPNsense stage: Caddy 80/443 and ingress firewall
scripts/deploy.py           Orchestrates VM, SSH bootstrap and global stage
scripts/router-bootstrap.py Idempotent script executed inside OPNsense over SSH
guest/nocloud-bootstrap/    Generic guest-side NoCloud package and tests
image/build.sh              Reproducible Proxmox QCOW2 build entrypoint
modules/caddy-reverse-proxy Application-owned domain-to-upstream module
modules/caddy-edge-ingress  Direct interface firewall ingress without NAT
examples/caddy-deployment   Composition examples for application repositories
```

## Quick start

Copy the environment examples and add local values:

```sh
cp tofu/terraform.tfvars.example tofu/terraform.tfvars
cp tofu/token.auto.tfvars.example tofu/token.auto.tfvars
cp router/terraform.tfvars.example router/terraform.tfvars
```

Keep the Proxmox API token outside `tofu/terraform.tfvars`:

```hcl
proxmox_api_token = "user@realm!token-id=token-secret"
```

Deploy the VM, prepare OPNsense over SSH, and apply the global router stage:

```sh
python3 scripts/deploy.py --ssh-private-key ~/.ssh/id_ed25519
```

The command remains interactive for both OpenTofu applies. Add `--auto-approve` only in a controlled automation environment. Runtime credentials are written to `.router/credentials.json` with mode `0600`; the public CA certificate is written to `.router/ca.pem`. Neither value is stored in OpenTofu state.

## Responsibility model

This repository owns the router platform and its global policy:

```text
VM and NoCloud
→ SSH readiness
→ API key generation
→ internal CA and WebUI certificate
→ WebUI on the management interface and port 10443
→ Caddy global settings on ports 80 and 443
→ global HTTP and HTTPS firewall pass rules
```

It must not contain application domains, application access lists, upstream server addresses, or application-specific Unbound records. Those belong to the repository that owns each server or service. Destroying an application repository must remove only its own Caddy domains, handlers, certificates, access lists, and DNS records without changing this global router configuration.

The base image remains universal. It contains required packages and generic NoCloud support but no environment-specific CA, WebUI port, Caddy listener configuration, domains, or API credentials.

## Build the OPNsense image

The repository contains both sides of the deployment contract. OpenTofu sends NoCloud data from the Proxmox side, while `os-nocloud-bootstrap` consumes it inside OPNsense.

Build the QCOW2 on the OPNsense build host:

```sh
./image/build.sh
```

The wrapper defaults to OPNsense `26.7.1`, the organization forks, and their `master` branches. Override `OPNSENSE_VERSION`, `GITBASE`, or an individual `*BRANCH` variable only when deliberately building another release or source tree.

The wrapper calls the OPNsense custom-image pipeline with:

```sh
make -C /usr/tools custom-vm,qcow2,20G,never,proxmox \
  ADDITIONS="os-qemu-guest-agent os-caddy /path/to/opnsense-proxmox/guest/nocloud-bootstrap /path/to/opnsense-proxmox/guest/caddy-policy"
```

The local guest packages install:

```text
/usr/local/opnsense/scripts/boot/nocloud_bootstrap.py
/usr/local/etc/rc.syshook.d/early/20-nocloud-bootstrap
/usr/local/etc/caddy/caddy.d/10-acme-ca.global
```

The source remains in this repository; it is not stored in the OPNsense core fork.

`os-caddy` is installed in every Proxmox image but remains disabled until it is configured. The local `os-caddy-policy` package pins automatic public certificate issuance to the Let's Encrypt ACME v2 production directory through the global import supported by `os-caddy`. The Terraform provider can manage Caddy settings, domains, handlers, access lists, automatic public ACME certificates and certificates issued by an existing OPNsense CA after deployment.

## Caddy reverse-proxy module

`modules/caddy-reverse-proxy` creates a Caddy domain and handler, with an optional access list. It accepts a domain that already exists in DNS and one or more internal upstream addresses. Public DNS and internal Unbound records remain outside the module so callers can use the DNS system appropriate for each environment.

The module supports public ACME certificates, dynamically issued certificates from an existing OPNsense CA, existing custom certificates, HTTP without TLS, HTTPS upstream trust, SNI, load balancing and health checks. See the module README for examples.

## Caddy edge-ingress module

`modules/caddy-edge-ingress` creates only two interface-scoped IPv4 pass rules for Caddy on ports 80 and 443. It does not create destination NAT, loopback translation, or alternate listener ports. This is the same packet flow used when the public NIC is attached directly to OPNsense through PCI passthrough.

The WebUI must already be bound to the management interface on a different port. The global `router/` stage enforces that contract before enabling Caddy. The module does not manage proxy domains, DNS, certificates, or interface assignments.

`examples/caddy-deployment` demonstrates application-owned reverse-proxy resources. Public DNS and server lifecycles remain outside the global router stage.

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

## Management IPv4 modes

`management_ipv4` is optional and uses a typed mode instead of overloading one string with unrelated meanings.

Keep the IPv4 configuration already stored in the image:

```hcl
management_ipv4 = {
  mode = "preserve"
}
```

Request DHCP for the management interface:

```hcl
management_ipv4 = {
  mode = "dhcp"
}
```

Apply a static address and optional gateway:

```hcl
management_ipv4 = {
  mode    = "static"
  address = "10.200.0.50/24"
  gateway = "10.200.0.1"
}
```

`preserve` is the default. In this mode OpenTofu omits `ipconfig0`; Proxmox therefore generates no physical network entry in `network-config`, and the bootstrap leaves the image's interface address, netmask and gateway unchanged. Hostname, DNS and administrative credentials are still processed.

Configurations created before this change must replace `management_address` and `management_gateway` with the `management_ipv4` object before the next `plan`.

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

The lifecycle stage exposes the values required by the SSH bootstrap:

- `management_ip`: actual IPv4 address reported for the management NIC;
- `management_netmask`: actual dotted-decimal netmask for that address;
- `cloudinit_username`: administrative SSH account created through NoCloud;
- `management_fqdn`: management hostname formed from `vm_name` and `dns_domain`.

The management NIC is matched by MAC address, not by assuming that the first global address belongs to it. The `bpg/proxmox` provider currently drops the prefix returned by QEMU Guest Agent, so `tofu/scripts/read-management-network.py` reads the raw Proxmox API response and preserves the prefix before calculating the netmask. It never prints the API token. The helper reads authentication from `PROXMOX_VE_API_TOKEN`, `PM_VE_API_TOKEN`, `TF_VAR_proxmox_api_token`, or the standard gitignored `tofu/token.auto.tfvars` file.

This works in `preserve`, `dhcp` and `static` modes. If the VM is stopped, the agent is disabled, or the management NIC has no usable IPv4 address, both outputs are `null`.

## Post-deployment bootstrap and verification

`scripts/deploy.py` waits for authenticated SSH after the VM apply, uploads the versioned bootstrap helper, and executes it with passwordless `sudo`. The helper:

- reuses a valid local API key or creates one with `opnsense-apikey`;
- creates or verifies the internal `biptec.net` CA without returning its private key;
- creates or verifies a management WebUI certificate with DNS and IP SANs;
- binds the WebUI to the management interface on HTTPS port `10443`;
- disables the automatic HTTP redirect so ports `80` and `443` remain free;
- verifies the new WebUI endpoint using the generated CA certificate.

The orchestration then imports the Caddy singleton into the global state, configures Caddy on `80/443`, and applies the ingress firewall rules. A completed command therefore verifies VM creation, SSH readiness, API authentication, trusted WebUI TLS, and the global OpenTofu apply. It does not create any application routes.

## Sensitive and local files

Do not commit:

- API tokens;
- `.router/credentials.json` and `.router/known_hosts`;
- `terraform.tfvars`;
- OpenTofu state;
- private SSH keys;
- QCOW2 or raw image files.

The provided `.gitignore` excludes these files. State can still contain sensitive resource data, so store it in an appropriately protected backend.

## Important defaults

- `vm_id = null`: Proxmox allocates the next free ID;
- `management_mac = null`: Proxmox generates a MAC address;
- `management_ipv4.mode = "preserve"`: keep IPv4 settings stored in the image;
- `cloudinit_datastore = null`: `vm_datastore` is used;
- `disk_size_gb = 21`;
- `cloudinit_username = "proxmox"`;
- `cloudinit_password = null`: no WebUI password is provisioned;
- `ssh_public_key_path = null`: SSH remains disabled;
- `qemu_agent_enabled = true`;
- QEMU Guest Agent IPv4 waiting is enabled;
- post-deployment WebUI port is `10443` on the management interface;
- the internal CA is `biptec.net`, RSA-4096, SHA-256, valid for 3650 days;
- Caddy listens directly on `80/443` with ACME email `webmaster@biptec.com`;
- global ingress defaults to `wanip`; the laboratory tfvars may override it;
- one VirtIO management NIC is created; extra NICs are optional.

Review `tofu/terraform.tfvars.example` and every variable description before applying the configuration to a new environment.
