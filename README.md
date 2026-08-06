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
- verify exact runtime listener ownership from FreeBSD `sockstat` output;
- verify primary/secondary authoritative DNS, DNSSEC, recursion isolation, transfers, and delegation;
- include the API extensions, BIND, and Caddy plugins required for declarative platform configuration;
- provide a reusable Caddy reverse-proxy module that maps a supplied domain to one or more internal upstreams;
- provide a reusable edge-ingress module that translates interface ports 80 and 443 to local Caddy listeners without exposing the WebUI;

## Requirements

- OpenTofu 1.12 or newer;
- Proxmox VE API access, including `VM.GuestAgent.Audit` on the deployed VM;
- `bpg/proxmox` provider 0.111.1;
- `hashicorp/external` provider 2.4.0;
- Python 3 on the OpenTofu runner for reading the raw Guest Agent network response;
- an OPNsense build environment with `/usr/tools` and `/usr/plugins` when producing a new image;
- the local packages in `guest/nocloud-bootstrap` and `guest/caddy-policy`, built together with `os-qemu-guest-agent`, `os-api-extensions`, `os-bind`, and `os-caddy`.

## Repository files

```text
tofu/                      OpenTofu deployment configuration and examples
  main.tf                  VM and image import configuration
  variables.tf             Inputs, defaults, validation and descriptions
  outputs.tf               VM ID, management IP/netmask and source image ID
  versions.tf              OpenTofu and provider requirements
  terraform.tfvars.example Non-secret configuration example
  token.auto.tfvars.example API token example
  scripts/                  Local helpers used by OpenTofu
guest/nocloud-bootstrap/   Guest-side NoCloud package and tests
image/build.sh             Pinned-source Proxmox QCOW2 build entrypoint
image/source-revisions.env.example Exact source revision configuration template
scripts/verify_listeners.py Exact service listener runtime verifier
examples/runtime-verification Listener contract and usage example
scripts/verify_dns.py       Authoritative DNS end-to-end verifier
examples/dns-verification   Primary/secondary verification contract
modules/caddy-reverse-proxy Reusable domain-to-upstream Caddy module; DNS remains external
modules/caddy-edge-ingress  Interface-scoped DNAT and firewall rules for local Caddy listeners
examples/caddy-deployment  Dual-ingress composition with public ACME and internal split DNS
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

Prepare exact source revisions on the OPNsense build host:

```sh
cp image/source-revisions.env.example image/source-revisions.env
```

Fill all five `*_COMMIT` values with full 40-character commit SHAs. The corresponding tools, core, ports, and src repositories must be on the configured branches, at those exact commits, and have clean working trees. The plugins commit only needs to exist in the local plugins repository because the wrapper archives the required plugin directories directly from that commit.

Then build the QCOW2:

```sh
./image/build.sh
```

The wrapper defaults to OPNsense `26.7.1`, but it no longer accepts implicit moving source revisions. It snapshots these plugins from the configured `PLUGINS_COMMIT` before invoking the OPNsense image pipeline:

```text
emulators/qemu-guest-agent
sysutils/api-extensions
dns/bind
www/caddy
```

The local NoCloud and Caddy policy packages are added from this repository. After a successful build, `image/build-manifest.json` records the exact commits, branches, image size, swap setting, profile, and plugin paths. This pins and records source inputs; it does not by itself claim byte-for-byte identical QCOW2 output across different build hosts.

The local guest packages install:

```text
/usr/local/opnsense/scripts/boot/nocloud_bootstrap.py
/usr/local/etc/rc.syshook.d/early/20-nocloud-bootstrap
/usr/local/etc/caddy/caddy.d/10-acme-ca.global
```

The source remains in this repository; it is not stored in the OPNsense core fork.

`os-api-extensions`, `os-bind`, and `os-caddy` are installed in every Proxmox image. BIND and Caddy remain disabled until they are configured, while API extensions make the management-service endpoints available immediately after bootstrap. The local `os-caddy-policy` package pins automatic public certificate issuance to the Let's Encrypt ACME v2 production directory through the global import supported by `os-caddy`. The Terraform provider can manage Caddy settings, domains, handlers, access lists, automatic public ACME certificates and certificates issued by an existing OPNsense CA after deployment.

## Caddy reverse-proxy module

`modules/caddy-reverse-proxy` creates a Caddy domain and handler, with an optional access list. It accepts a domain that already exists in DNS and one or more internal upstream addresses. Public DNS and internal Unbound records remain outside the module so callers can use the DNS system appropriate for each environment.

The module supports public ACME certificates, dynamically issued certificates from an existing OPNsense CA, existing custom certificates, HTTP without TLS, HTTPS upstream trust, SNI, load balancing and health checks. See the module README for examples.

## Caddy edge-ingress module

`modules/caddy-edge-ingress` creates interface-scoped IPv4 DNAT and pass rules for ports 80 and 443. It translates those requests to Caddy on loopback ports 8080 and 8443 while management-interface traffic continues to reach the OPNsense WebUI. The module does not manage global Caddy settings, proxy domains, DNS, or interface assignments. See the module README for the required singleton settings import and usage examples.

`examples/caddy-deployment` shows the complete composition: a public ingress for ACME-backed domains, a separate internal service ingress, an existing internal CA, and an Unbound split-DNS record. Public DNS and interface/VIP lifecycles remain outside the example.

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

Only two management-network outputs are exposed:

- `management_ip`: actual IPv4 address reported for the management NIC;
- `management_netmask`: actual dotted-decimal netmask for that address.

The management NIC is matched by MAC address, not by assuming that the first global address belongs to it. The `bpg/proxmox` provider currently drops the prefix returned by QEMU Guest Agent, so `tofu/scripts/read-management-network.py` reads the raw Proxmox API response and preserves the prefix before calculating the netmask. It never prints the API token. The helper reads authentication from `PROXMOX_VE_API_TOKEN`, `PM_VE_API_TOKEN`, `TF_VAR_proxmox_api_token`, or the standard gitignored `tofu/token.auto.tfvars` file.

This works in `preserve`, `dhcp` and `static` modes. If the VM is stopped, the agent is disabled, or the management NIC has no usable IPv4 address, both outputs are `null`.

## Post-deployment verification

OpenTofu finishes after Proxmox creates and starts the VM. It does not attempt SSH access or an OPNsense API readiness check. Verify the first boot and bootstrap result manually through the Proxmox console.

A successful `apply` confirms that the requested Proxmox resources were created; it does not prove that every guest service is ready.

## Sensitive and local files

Do not commit:

- API tokens;
- `terraform.tfvars`;
- OpenTofu state;
- private SSH keys;
- QCOW2 or raw image files;
- `image/source-revisions.env` and generated `image/build-manifest.json`.

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
- one VirtIO management NIC is created; extra NICs are optional.

Review `tofu/terraform.tfvars.example` and every variable description before applying the configuration to a new environment.
