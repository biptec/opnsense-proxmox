# Primary router platform root

This root composes the shared Etna router state. It owns shared L3 transport and router-hosted services, not site-specific DNS records, reverse-proxy domains, handlers, or backend policy.

## Proxmox prerequisites

The Proxmox host remains a separate, persistent management domain:

- `vmbr0` is the untagged management bridge used by Etna NIC0;
- `vmbr1` is the VLAN-aware trunk bridge used by Etna NIC1;
- the provider-facing physical WAN NIC is an access port for VLAN `3801` on `vmbr1`;
- provider-facing Ethernet is untagged; Etna sees VLAN `3801` tagged;
- the current `bpg/proxmox` bridge resource does not expose per-port `bridge-access`, so this host-port setting is a prerequisite rather than a router-state resource.

Do not move the live Proxmox WAN address/gateway during a test apply. The host-side cutover is a separate reviewed operation.

`vm-bootstrap.tfvars.example` is the Etna-owned overlay for the generic `../../tofu` VM root. It now carries the known Etna node/storage/network values, including `local-vmdata01`.

The VM bootstrap and router configuration intentionally use two Terraform states, but they are one Etna ownership domain. The split is a bootstrap dependency, not an architectural ownership split: the OPNsense provider cannot read/import/configure Etna until the VM exists, boots, and exposes its API. Keep both Etna value files in this directory; apply the VM bootstrap state first, then the primary-router state. Destroy in reverse order.

Copy `vm-bootstrap.tfvars.example` to the gitignored `vm-bootstrap.tfvars`, add the normal secret/image inputs outside Git, then run the generic VM root with that Etna overlay:

```sh
cp vm-bootstrap.tfvars.example vm-bootstrap.tfvars
tofu -chdir=../../tofu apply -var-file=../platform/primary-router/vm-bootstrap.tfvars
```

## Bootstrap

The OPNsense image already contains `os-api-extensions`, `os-bind`, and `os-caddy`. Create the initial API key through the approved SSH bootstrap, then export:

```text
OPNSENSE_URI
OPNSENSE_API_KEY
OPNSENSE_API_SECRET
OPNSENSE_ALLOW_INSECURE
```

When `webgui_certificate_ref = null`, the read-only helper discovers the certificate already used by WebGUI. Credentials are read only from the environment and are never printed.

A clean OPNsense installation already has singleton WebGUI, SSH, BIND, and Caddy settings. After `tofu init`, adopt those objects into this state before the first platform apply:

```sh
STATE_PATH=terraform.tfstate VAR_FILE=terraform.tfvars ./scripts/import-singletons.sh
```

The helper is idempotent and uses only `tofu state show` and `tofu import`; it does not write OPNsense configuration outside Terraform.

## Ownership

This state owns only Etna and shared transport:

- VLAN `3801` WAN and its default gateway;
- VLAN `3802` routed public transport;
- Etna management IP aliases;
- portable DNS1, NTP1, reverse-proxy, and Source NAT `/30` loopbacks and reserved VLAN identities;
- BIND/reverse-proxy base settings and NTP1 service binding;
- dedicated outbound-NAT identity and shared NO-NAT policy when explicitly activated.

It does **not** pre-create downstream host/service VLANs, routes, firewall rules, secondary DNS configuration, or application-specific resources. Each downstream Terraform state owns both its workload and every additive Etna resource required by that workload. Destroying that state therefore removes its router integration as well.

The VM bootstrap state owns Etna's primary management IPv4 `10.16.214.2/30`. Downstream states may consume primary outputs such as the shared VLAN `3802` interface and BIND zone IDs, but must not own or delete shared transport or Etna-local services.

The primary state must outlive every downstream state. Destroy downstream workloads first so each state can remove its own Etna integration before shared interfaces/zones are removed.

## Safe first apply

All cutover flags default to false. The initial platform apply therefore does not attach the public DNS/proxy/SNAT VIPs and does not enable the reverse proxy or client-facing NTP service. DNS service ownership and ingress firewall cutover are added in the next platform stage.

The first ownership apply intentionally changes the imported WebGUI/SSH listener configuration, so run it once with `allow_management_readdress = true`. Use `-parallelism=1`: OPNsense serializes configd writes and a parallel first apply can create a long lock queue. After that apply succeeds, immediately apply the same safe configuration again with the default `allow_management_readdress = false` to relock the guard. Subsequent plans should keep the guard false unless a reviewed management readdress is intentional.

`terraform.tfvars.example` contains only approved Etna and shared-transport addressing. Downstream addressing belongs to its own state. Copy it to a gitignored `.tfvars` file for the test deployment; secrets stay in environment variables.

## DNS and firewall cutover

The root creates BIND ACLs, destination-aware internal/public views, two copies of the `biptec.net` primary zone, DNSSEC signing, and only platform-owned service records. Site/application records remain outside this state and consume the exported zone/view IDs.

The safe state is:

```hcl
cutover = {}
```

This keeps Unbound on port 53 and leaves the public DNS VIP detached. To move DNS ownership to BIND, change both values in the same reviewed plan:

```hcl
cutover = {
  dns_target        = "bind"
  allow_dns_cutover = true
  public_dns_vip    = true
}
```

The dependency graph attaches the VIP, runs the guarded DNS cutover, verifies BIND, and only then enables WAN TCP/UDP 53 rules. This avoids a window where wildcard Unbound is publicly reachable through the DNS VIP. After a successful transition, return `allow_dns_cutover` to `false` while keeping `dns_target = "bind"` and `public_dns_vip = true`.

Internal DNS recursion is allowed only for `trusted_internal_networks` and only on the internal DNS destination. The public view matches the public DNS destination, permits authoritative queries, and has recursion disabled.

NTP has no WAN rule. Internal UDP/123 opens only when `ntp_serving = true`. Public reverse-proxy TCP/80 and TCP/443 opens only when the proxy service and its public VIP are explicitly activated. Primary-owned internal service and management rules apply on every Etna ingress interface except WAN, constrained by their source/destination identities; this lets future downstream states reach primary services without the primary state enumerating their interfaces. The outbound NAT mode is always owned by this state: `automatic` while egress is safe/detached and `hybrid` while explicit NO-NAT/SNAT rules are active. Downstream states own the firewall pass rules that permit their workloads to use that shared egress policy.

## Management endpoint cutover

OPNsense binds WebGUI/API and SSH by logical interface, so both daemons can see all bindable addresses on the shared management NIC. Firewall policy provides the intended endpoint split.

Do not enable the cross-address blocks while the Terraform provider still connects to `10.16.214.2`. First create `10.16.214.6`, verify WebGUI/API there, switch `OPNSENSE_URI` to the `.6` endpoint, then apply:

```hcl
cutover = {
  management_endpoint_firewall = true
  # retain the other already-selected cutover values here
}
```

The final policy permits SSH on `.2:22`, WebGUI/API on `.6:443`, and blocks the inverse port/address combinations. These destination rules apply on every Etna ingress interface except WAN, so current and future VPN/VLAN clients get the same endpoint split without being declared in this state, while the direct Proxmox rescue path remains available. The same policy is applied to the configured IPv6 management identities.

## Downstream integration contract

The primary root intentionally contains no Rigi/VPN/Uyuni/Directory-specific configuration. It exports shared identifiers (`wan_interface`, `routed_interfaces`, BIND view/zone IDs, and service addresses) for downstream states.

For example, the secondary-DNS state creates Rigi and also creates its VLAN `508`, VLAN `2804`, VLAN `2820`, Etna-side gateway addresses, firewall rules, NS2 records, TSIG key, and primary-zone transfer attachment. Its destroy removes those resources while leaving the primary zones and shared VLAN `3802` intact.

The safe state also returns outbound NAT mode to `automatic`; it does not merely remove NAT resources from Terraform state.
