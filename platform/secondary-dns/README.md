# Secondary DNS and NTP platform root

This root owns Rigi as an independent platform state. Rigi is an immutable Ubuntu 24.04 LTS VM created by Terraform; cloud-init configures networking, BIND, Chrony, nftables, SSH hardening, and QEMU Guest Agent. No Ansible, Salt, Terraform remote-exec, or post-bootstrap SSH configuration is used.

## Proxmox topology

Rigi uses `vmbr1` for both NICs:

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

Each view sets an explicit `transfer-source`, so AXFR/IXFR refreshes use the same stable Rigi identity that clients use. Transfers and NOTIFY are authenticated with one dedicated TSIG key. The primary state owns the matching key and `also-notify` configuration.

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

Output is allowed so the secondary can fetch packages, synchronize time, resolve recursively for internal clients, and transfer zones. Etna separately controls forwarding between these networks and the Internet.

## Immutable lifecycle

The Ubuntu cloud image is pinned by exact release URL and SHA-256. A hash of the rendered network data, user data, and image checksum drives `replace_triggered_by`. Configuration changes replace Rigi instead of attempting to rerun cloud-init on an existing VM.

This is intentional for a secondary service: Etna remains authoritative and provides NTP1 during Rigi replacement.

## Secrets

`transfer_tsig_secret` and the optional SSH public key are never committed. The TSIG secret is necessarily present in the protected Terraform state and in the Terraform-managed cloud-init snippet. Protect the backend and Proxmox snippet datastore accordingly.

Copy `terraform.tfvars.example` to a gitignored file and supply the Proxmox token and transfer secret separately. Replace only the `vm_datastore` placeholder with the same datastore used by the current test environment.
