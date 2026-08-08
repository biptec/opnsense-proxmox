# Production deployment runbook

This runbook covers the first production deployment of Etna and Rigi. It deliberately separates router cutover from public-service activation.

## Non-negotiable rules

- Do not change the provider-facing configuration on Tofana during the pre-cutover Etna validation phase.
- Keep the provider-facing physical NIC disconnected from VLAN `3801` until the router-only cutover. Etna may carry VLAN `3801` on its internal trunk before then.
- Keep public DNS WAN ingress, reverse proxy, and outbound NAT disabled until their explicit activation phase.
- Keep the Etna VM bootstrap, primary-router, and secondary-dns Terraform states separate.
- Never destroy primary-router while a downstream state still references it.
- Every apply is followed by a second `tofu plan`; continue only on `No changes`.
- At every stop gate, prefer rollback over improvising a live production fix.

The committed `terraform.tfvars.example` files are the production addressing and L2 identity source of truth. Secrets, image locations, API tokens, and the transfer TSIG secret stay outside Git.

## Fixed production identities

Etna WAN IPv4 is `138.201.128.112/26`, gateway `138.201.128.65`. Etna WAN IPv6 is `2a01:4f8:172:2bae::112/64`, gateway `fe80::1`.

Router-local public identities are `138.201.128.87` / `2a01:4f8:172:2bae::87` for reverse proxy, `.88` / `::88` for DNS1, and `.95` / `::95` for Source NAT/NAT66.

The shared routed-public transport is VLAN `3802`: Etna uses `5.9.227.113` and `2a01:4f8:fff3:107::113`; Rigi uses `5.9.227.114` and `2a01:4f8:fff3:107::114`.

The provider-facing MAC is `90:1b:0e:95:a1:0b`. Terraform assigns it to Etna NIC1 from the first boot. Tofana uses three distinct MAC identities during normal runtime: Etna WAN keeps `90:1b:0e:95:a1:0b`, `vmbr1` is pinned to `72:36:cd:de:1d:28`, and physical `nic0` temporarily uses locally-administered `92:1b:0e:95:a1:0b`. A reboot restores the physical NIC hardware MAC together with the persistent rescue bridge configuration.

## Phase 0: preflight

Work from a clean checkout of the approved `master`. Confirm the Proxmox API endpoint/token, the pinned OPNsense image input, the Ubuntu image checksum already committed for Rigi, and protected storage/backups for all three Terraform states.

Copy only the tracked examples; keep the resulting files gitignored:

```sh
cp platform/primary-router/vm-bootstrap.tfvars.example platform/primary-router/vm-bootstrap.tfvars
cp platform/primary-router/terraform.tfvars.example platform/primary-router/terraform.tfvars
cp platform/secondary-dns/terraform.tfvars.example platform/secondary-dns/terraform.tfvars
```

Supply Proxmox credentials/image inputs outside Git. Before applying, verify that Tofana `nic0` still has MAC `90:1b:0e:95:a1:0b`.

Prepare the two non-provider bridges **without moving `nic0` or the live WAN address**:

- make `vmbr1` VLAN-aware, allow the production VLAN range, and pin its bridge MAC to `72:36:cd:de:1d:28`;
- create host-only `vmbr2` for Etna management. Tofana uses `10.16.214.1/30` and `10.16.214.5/30`; Etna uses `.2` and `.6`. Configure the corresponding Tofana IPv6 peers `2a07:e580:a10:d600::1/64` and `2a07:e580:a10:d604::1/64`;
- keep `vmbr0` unchanged as the live rescue/WAN bridge with `nic0`, `138.201.128.112/26`, and gateway `138.201.128.65`.

The current legacy `10.200.0.0/24` address and NAT/DNAT/FORWARD rules may remain active during pre-cutover validation if existing workloads still need them. They are not part of the final persistent rescue configuration and must be removed from the staged `/etc/network/interfaces` before the first WAN handoff. Do not reload that final file yet.

Etna uses host-only `vmbr2` for management and its final unrestricted `vmbr1` trunk from first boot, including VLAN `3801`. NIC1 already carries the provider-facing MAC. This is safe because physical `nic0` remains on separate rescue `vmbr0`; there is no provider-facing L2 path from `vmbr1`.

**Stop gate:** do not continue if Tofana lacks console/reset access, `vmbr2` cannot reach Etna management after deployment, state backup is unavailable, or physical `nic0` is already a member of `vmbr1`.

## Phase 1: deploy Etna VM with WAN physically isolated

From the repository root:

```sh
tofu -chdir=tofu init
tofu -chdir=tofu plan \
  -var-file=../platform/primary-router/vm-bootstrap.tfvars

tofu -chdir=tofu apply \
  -var-file=../platform/primary-router/vm-bootstrap.tfvars
```

Verify Etna boots and is configured `onboot=1`, QEMU Guest Agent becomes ready, management SSH answers on `10.16.214.2` through host-only `vmbr2`, and NIC1 has MAC `90:1b:0e:95:a1:0b` on the unrestricted `vmbr1` trunk. Confirm physical `nic0` still belongs only to `vmbr0`.

Create the initial OPNsense API key through the approved SSH bootstrap and export `OPNSENSE_URI`, `OPNSENSE_API_KEY`, `OPNSENSE_API_SECRET`, and `OPNSENSE_ALLOW_INSECURE` as appropriate.

## Phase 2: primary-router safe ownership

Initialise and adopt the singleton settings:

```sh
tofu -chdir=platform/primary-router init
cd platform/primary-router
STATE_PATH=terraform.tfstate VAR_FILE=terraform.tfvars ./scripts/import-singletons.sh
cd ../..
```

The first apply is intentionally serialized and explicitly approves the management listener readdress:

```sh
tofu -chdir=platform/primary-router apply -parallelism=1 \
  -var-file=terraform.tfvars \
  -var='allow_management_readdress=true'
```

Verify both management addresses exist. Confirm WebGUI/API on `10.16.214.6`, then change `OPNSENSE_URI` to that endpoint before enabling the endpoint-split firewall.

Apply the same configuration again with the guard relocked:

```sh
tofu -chdir=platform/primary-router apply -parallelism=1 \
  -var-file=terraform.tfvars

tofu -chdir=platform/primary-router plan -parallelism=1 \
  -var-file=terraform.tfvars
```

The second plan must report `No changes`.

## Phase 3: stage BIND and internal services

Before Rigi can consume the primary contract, move DNS ownership from Unbound to BIND while the provider-facing physical NIC is still disconnected from VLAN `3801`. Set the local primary `cutover` block to:

```hcl
cutover = {
  dns_target                   = "bind"
  allow_dns_cutover            = true
  public_dns_vip               = true
  public_dns_ingress           = false
  management_endpoint_firewall = true
  ntp_serving                  = true
}
```

Apply with `-parallelism=1`. After the guarded transition succeeds, immediately set `allow_dns_cutover = false`, apply again, and require a clean second plan.

At this point BIND owns DNS locally and the DNS VIPs exist, but public DNS WAN rules remain disabled. Reverse proxy and outbound NAT remain disabled. NTP is internal-only.

Generate the downstream contract for Rigi:

```sh
tofu -chdir=platform/primary-router output -json downstream_router_contract \
  | jq '{primary_router: .}' \
  > platform/secondary-dns/primary-router.auto.tfvars.json
```

Initialise secondary-dns and review its plan, but do not apply it yet:

```sh
tofu -chdir=platform/secondary-dns init
tofu -chdir=platform/secondary-dns plan -var-file=terraform.tfvars
```

Rigi cloud-init installs packages from Ubuntu repositories and its normal Internet path is VLAN `3802` through Etna. Before the provider-facing physical NIC is mapped to VLAN `3801`, Etna has no provider WAN path, so a full production Rigi apply cannot complete without a temporary egress workaround. The approved sequence avoids such a workaround: only the plan is reviewed before router cutover.

**Stop gate:** Etna management, BIND internal DNS, NTP1, primary state, and the secondary plan must all be clean before touching Tofana WAN ownership.

## Phase 4: router-only WAN cutover

The first cutover uses `proxmox-wan-cutover`; it does **not** persist the production L2 handoff. Before the maintenance window, install it on Tofana in its default disarmed state and create `/etc/wan-cutover.conf` with these production values:

```bash
TARGET_VM_ID=<tofu-output-vm_id>
TARGET_VM_NAME="etna"
TARGET_WAN_NET_INDEX=1
TARGET_WAN_MAC="90:1b:0e:95:a1:0b"
WAN_INTERFACE="nic0"
RESCUE_BRIDGE="vmbr0"
HOST_PUBLIC_CIDR="138.201.128.112/26"
HOST_PUBLIC_GATEWAY="138.201.128.65"
PROVIDER_MAC="90:1b:0e:95:a1:0b"
PRODUCTION_BRIDGE="vmbr1"
PRODUCTION_BRIDGE_MAC="72:36:cd:de:1d:28"
WAN_VLAN_ID=3801
RUNTIME_WAN_MAC="92:1b:0e:95:a1:0b"
HOST_ROUTER_INTERFACE="vmbr2"
TARGET_ROUTER_IP="10.16.214.2"
```

Stage the final persistent `/etc/network/interfaces` as the **rescue state**: `vmbr0` owns `nic0` plus the public IP/gateway, `vmbr1` is VLAN-aware with no physical port, and `vmbr2` is host-only management. Remove the old `10.200.0.0/24` NAT/DNAT/FORWARD directives from this staged persistent file. Do not persist `nic0 -> vmbr1`; normal production handoff is runtime-only.

Back up the previous network file and verify `wan-cutover validate`. It must prove Etna is already running, NIC1 has the provider MAC on `vmbr1`, `vmbr1` is VLAN-aware with its distinct bridge MAC, Tofana reaches `10.16.214.2` through `vmbr2`, and `nic0` still owns the direct rescue WAN on `vmbr0`.

Perform the first handoff without rebooting:

```bash
wan-cutover cutover-now
wan-cutover status
```

The runtime operation removes the public address/default route from `vmbr0`, detaches `nic0`, changes only the host-side physical NIC MAC to `92:1b:0e:95:a1:0b`, attaches it to `vmbr1` as untagged access/PVID VLAN `3801`, and installs Tofana's default route through Etna management `10.16.214.2`. Etna stays running and Terraform state is not modified.

If Tofana management remains reachable and WAN validation fails, use `wan-cutover rollback-now`. If Tofana becomes unreachable, reset/reboot it: the persistent rescue configuration restores direct WAN to Tofana. The automatic service remains disarmed during this first acceptance test, so a reboot cannot hand WAN back to Etna on its own.

Do not enable any public-service ingress at this stage. Primary BIND may remain active with its VIP attached because `public_dns_ingress = false` keeps WAN TCP/UDP 53 blocked.

Verify Etna can reach IPv4 gateway `138.201.128.65` and IPv6 gateway `fe80::1`, then verify outbound IPv4/IPv6 from Etna itself. Confirm the primary WAN identities are present and no NTP listener exists on WAN.

The Hetzner Failover `/64` remains routed to the Tofana server target. Verify delivery of `2a01:4f8:fff3:107::/64` after the MAC/trunk transition before changing any public DNS delegation.

After basic WAN is proven, activate router egress while keeping public ingress closed:

```hcl
cutover = {
  dns_target                   = "bind"
  public_dns_vip               = true
  public_dns_ingress           = false
  management_endpoint_firewall = true
  ntp_serving                  = true
  egress_vip                   = true
  outbound_nat                 = true
}
```

Apply and verify IPv4 SNAT uses `138.201.128.95`, IPv6 stateful NAT66 uses `2a01:4f8:172:2bae::95`, and both routed-public networks remain NO-NAT. Require a clean follow-up plan.

**Rollback gate:** if management, gateway reachability, NAT, or provider IPv6 delivery is wrong, stop here. Prefer `wan-cutover rollback-now` while Tofana management is available; otherwise reboot/reset Tofana. Both paths restore `nic0` to rescue `vmbr0` with hardware MAC `90:1b:0e:95:a1:0b`, the public IP, and provider default route. Do not continue to Rigi or public services.

After a successful first handoff, perform one deliberate reboot recovery test before enabling automation. Confirm direct SSH to Tofana during the recovery window, run `wan-cutover disarm`, and verify the host remains in rescue state. Only after that test succeeds run `wan-cutover arm` for future delayed automatic handoffs.

## Phase 5: deploy and lifecycle-test Rigi

Regenerate `primary-router.auto.tfvars.json` after the router cutover. Keep `public_dns_ingress = false` in the local secondary tfvars and supply `transfer_tsig_secret` outside Git.

```sh
tofu -chdir=platform/secondary-dns plan -var-file=terraform.tfvars
tofu -chdir=platform/secondary-dns apply -var-file=terraform.tfvars
tofu -chdir=platform/secondary-dns plan -var-file=terraform.tfvars
```

The final plan must be clean. Verify:

- Rigi management on `10.16.222.2` and its approved IPv6 identity;
- VLAN `2804` DNS2 and VLAN `2820` NTP2 source-policy routing;
- `5.9.227.114` and `2a01:4f8:fff3:107::114` on VLAN `3802` without NAT;
- internal and public BIND views receive AXFR/IXFR and NOTIFY from Etna using TSIG;
- NTP2 serves only its internal identities;
- external DNS2 TCP/UDP 53 is still blocked by Etna because `public_dns_ingress = false`.

Then prove ownership by destroying only secondary-dns:

```sh
tofu -chdir=platform/secondary-dns destroy -var-file=terraform.tfvars
tofu -chdir=platform/primary-router plan -parallelism=1 -var-file=terraform.tfvars
```
Primary-router must remain `No changes`. Confirm Rigi VM, VLANs `508/2804/2820`, Rigi firewall rules, NS2 records, transfer attachments, and TSIG are gone while shared VLAN `3802` and both primary zones remain.

Reapply secondary-dns and require clean plans from both states. This is the final lifecycle gate before any public DNS activation.

## Phase 6: activate public services

Activate DNS2 first by setting in the secondary state:

```hcl
public_dns_ingress = true
```

Apply and verify external TCP/UDP 53 over both `5.9.227.114` and `2a01:4f8:fff3:107::114`. NTP2 UDP/123 must remain unreachable publicly.

Then activate DNS1 by setting in primary `cutover`:

```hcl
public_dns_ingress = true
```

Keep the other already-enabled primary cutover fields unchanged. Verify authoritative DNS1 over IPv4/IPv6, DNSSEC, NS1/NS2 consistency, recursion isolation, and zone transfer health.

Reverse proxy remains disabled until its downstream/site configuration is ready. Only then set `public_proxy_vip = true` and `proxy_enabled = true` in the same reviewed primary plan.

## Completion criteria

The platform is accepted only when all three states have clean plans, DNS1/DNS2 answer correctly over IPv4 and IPv6, NTP1/NTP2 remain internal-only, NAT44/NAT66 use the dedicated `.95`/`::95` identities, and `5.9.227.112/29` plus `2a01:4f8:fff3:107::/64` are routed without NAT.

After acceptance, archive the protected state backups and the final Tofana network backup. Remove one-time API/bootstrap credentials. Keep the rollback instructions until the platform has completed an agreed stability period.
