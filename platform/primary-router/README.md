# Primary router platform root

This root composes the shared Etna router state. It owns common L3 networking and router-hosted services, not site-specific DNS records, Caddy domains, handlers, or backend policy.

## Proxmox prerequisites

The Proxmox host remains a separate, persistent management domain:

- `vmbr0` is the untagged management bridge used by Etna NIC0;
- `vmbr1` is the VLAN-aware trunk bridge used by Etna NIC1;
- the provider-facing physical WAN NIC is an access port for VLAN `3801` on `vmbr1`;
- provider-facing Ethernet is untagged; Etna sees VLAN `3801` tagged;
- the current `bpg/proxmox` bridge resource does not expose per-port `bridge-access`, so this host-port setting is a prerequisite rather than a router-state resource.

Do not move the live Proxmox WAN address/gateway during a test apply. The host-side cutover is a separate reviewed operation.

`tofu/etna.tfvars.example` contains only the Etna VM networking overlay. Existing test-node, storage, and image values remain unchanged.

## Bootstrap

The OPNsense image already contains `os-api-extensions`, `os-bind`, and `os-caddy`. Create the initial API key through the approved SSH bootstrap, then export:

```text
OPNSENSE_URI
OPNSENSE_API_KEY
OPNSENSE_API_SECRET
OPNSENSE_ALLOW_INSECURE
```

When `webgui_certificate_ref = null`, the read-only helper discovers the certificate already used by WebGUI. Credentials are read only from the environment and are never printed.

## Ownership

This state owns:

- VLAN `3801` WAN and its default gateway;
- every routed VLAN listed in the Etna routing inventory;
- VLAN `3802` routed public transport;
- the VPN client static route through Vela;
- Etna management IP aliases;
- portable DNS, NTP, Caddy, and NAT `/30` loopbacks and reserved VLAN identities;
- BIND/Caddy base settings and NTP service binding;
- dedicated outbound-NAT identity and NO-NAT policy when explicitly activated.

The VM bootstrap state owns Etna's primary management IPv4 `10.16.214.2/30`. Site states must not manage any resource listed above.

## Safe first apply

All cutover flags default to false. The initial platform apply therefore does not attach the public DNS/Caddy/SNAT VIPs and does not enable Caddy or client-facing NTP service. DNS service ownership and ingress firewall cutover are added in the next platform stage.

`terraform.tfvars.example` contains the approved Etna/Rigi production-like addressing. Copy it to a gitignored `.tfvars` file for the test deployment; secrets stay in environment variables.

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

Internal DNS recursion is allowed only for `dns_internal_client_networks` and only on the internal DNS destination. The public view matches the public DNS destination, permits authoritative queries, and has recursion disabled.

NTP has no WAN rule. Internal UDP/123 opens only when `ntp_serving = true`. Public Caddy TCP/80 and TCP/443 opens only when Caddy and its public VIP are explicitly activated. General IPv4 egress opens with outbound NAT and excludes RFC1918 destinations, so enabling Internet access does not implicitly enable lateral private-network routing.

## Management endpoint cutover

OPNsense binds WebGUI/API and SSH by logical interface, so both daemons can see all bindable addresses on the shared management NIC. Firewall policy provides the intended endpoint split.

Do not enable the cross-address blocks while the Terraform provider still connects to `10.16.214.2`. First create `10.16.214.6`, verify WebGUI/API there, switch `OPNSENSE_URI` to the `.6` endpoint, then apply:

```hcl
cutover = {
  management_endpoint_firewall = true
  # retain the other already-selected cutover values here
}
```

The final policy permits SSH on `.2:22`, WebGUI/API on `.6:443`, and blocks the inverse port/address combinations. The same policy is applied to the configured IPv6 management identities.

## Secondary DNS integration

Rigi is a separate Terraform state. Keep `secondary_dns.enabled = false` until that state is ready to create the VM. Then supply the same protected transfer TSIG secret to both states and enable secondary integration in this root.

Enabling Rigi adds, in the same primary state:

- one dedicated BIND transfer TSIG key;
- authenticated `allow-transfer`/`also-notify` on both internal and public `biptec.net` zone copies;
- internal `ns2` -> `10.16.18.53` (+ IPv6) and public `ns2` -> `5.9.227.114`;
- internal DNS2 and NTP2 firewall policy;
- public TCP/UDP 53 forwarding to `5.9.227.114`;
- routed-public egress for Rigi without NAT;
- no public UDP/123 rule.

Rigi's public refresh/transfer traffic to the primary DNS VIP is explicitly allowed from VLAN `3802`. The routed-public `/29` remains covered by the platform NO-NAT policy.
