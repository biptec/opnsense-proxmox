# Secondary DNS and NTP platform root

This root owns the complete Rigi lifecycle: the VM itself **and every Rigi-specific integration resource on Etna**. Rigi is an immutable Ubuntu 24.04 LTS VM created by Terraform; cloud-init configures networking, BIND, Chrony, nftables, SSH hardening, and QEMU Guest Agent. No Ansible, Salt, Terraform remote-exec, or post-bootstrap SSH configuration is used.

The primary-router state knows nothing about Rigi. This state consumes only shared primary outputs and creates VLAN `508`, VLAN `2804`, VLAN `2820`, their Etna gateway assignments, Rigi firewall policy, NS2 records, TSIG, and transfer attachments. Shared WAN and VLAN `3802` remain owned by the primary state and are never deleted here; VLAN ID, subnet, gateway, and logical OPNsense interface are consumed from the primary contract rather than duplicated.

Do not copy primary-router identifiers into this configuration by hand. After the primary state is applied, generate a gitignored `primary-router.auto.tfvars.json` from its single `downstream_router_contract` output as shown in `terraform.tfvars.example`. That contract includes dynamic OPNsense logical interface names/zone UUIDs plus the shared routed-public transport metadata. These are references only; do not import the referenced primary resources into this state. The secondary plan is rejected unless `dns_active_service` is `bind`, so NS2 cannot be published before the primary DNS cutover is complete.

## Proxmox topology

Rigi uses `vmbr1` for both NICs. Its VM disk is stored on `local-vmdata01`:

- NIC0 is configured by Proxmox as access VLAN `508`, so Rigi receives management untagged;
- NIC1 is an explicit trunk containing only VLANs `2804`, `2820`, and `3802`.

Fixed MAC addresses let Netplan rename the NICs deterministically to `mgmt0` and `trunk0` before VLAN interfaces are created.

## Network identities

```text
mgmt0          10.16.222.2/30                    management
alcor.2804     10.16.18.53/30                    DNS2 internal
               2a07:e580:a10:1234::2/64
kochab.2820    10.16.18.122/30                   NTP2 internal
               2a07:e580:a10:1278::2/64
public.3802    5.9.227.114/29                    DNS2 public only
```

Netplan installs source-policy tables for every L3 identity. Replies sourced from each service identity therefore return through the matching Etna gateway. The main Internet default uses routed-public VLAN `3802`; internal destinations have an explicit main-table route through Alcor.

## DNS

BIND uses two destination-aware views of the same zone:

- `internal` listens on Alcor, receives the internal `biptec.net` secondary zone from Etna's internal DNS endpoint, and by default provides recursion only to trusted internal networks;
- `public` listens only on `5.9.227.114`, receives the public secondary zone from `138.201.128.88`, and never enables recursion.

Each view sets an explicit `transfer-source`, so AXFR/IXFR refreshes use the same stable Rigi identity that clients use. Transfers and NOTIFY are authenticated with one dedicated TSIG key. This state owns the matching TSIG key and additive transfer attachments on both existing primary zones; deleting this state clears only those attachments and does not delete either primary zone.

`internal_recursion_enabled` can disable recursion on Alcor without affecting its secondary-authoritative role. Public recursion cannot be enabled by this root.

## NTP

Chrony binds NTP service sockets only to Kochab's IPv4 and IPv6 identities. Trusted internal networks are allowed; no public UDP/123 rule exists. The routed-public address is never an NTP endpoint.

## Firewall

nftables defaults input and forwarding to drop. It permits only:

- management SSH from trusted internal networks;
- internal DNS TCP/UDP 53 on Alcor;
- internal NTP UDP 123 on Kochab;
- public DNS TCP/UDP 53 on `5.9.227.114`;
- ICMP/ICMPv6 and established traffic.

Output is allowed so the secondary can fetch packages, synchronize time, resolve recursively for internal clients, and transfer zones. The same state creates the required Etna firewall rules. Trusted-client service rules apply on every Etna ingress interface except WAN, so they do not need to know which current or future internal VLAN delivered the packet.

## Immutable lifecycle

The Ubuntu cloud image is pinned by exact release URL and SHA-256. A hash of the rendered network data, user data, and image checksum drives `replace_triggered_by`. Configuration changes replace Rigi instead of attempting to rerun cloud-init on an existing VM.

This is intentional for a secondary service: Etna remains authoritative and provides NTP1 during Rigi replacement.

## Secrets

`transfer_tsig_secret` and the optional SSH public key are never committed. The TSIG secret is necessarily present in the protected Terraform state and in the Terraform-managed cloud-init snippet. Protect the backend and Proxmox snippet datastore accordingly.

Copy `terraform.tfvars.example` to a gitignored file and supply the Proxmox token and transfer secret separately. Replace only the `vm_datastore` placeholder with the same datastore used by the current test environment.

## Destroy semantics

`tofu destroy` first detaches the Rigi-specific DNS integration (NS2 records and transfer attachments), then removes the VM, and finally removes its firewall rules, Etna assignments, and VLANs. The TSIG key is removed only after both transfer attachments no longer reference it. The shared primary zones, WAN, and routed-public VLAN `3802` are references only and remain untouched.

Run this destroy before destroying the primary-router state; the primary zone/interface references are intentionally not duplicated or owned here.
