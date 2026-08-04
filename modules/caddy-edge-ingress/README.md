# Caddy edge ingress module

Creates IPv4 firewall rules that expose Caddy directly on one OPNsense ingress interface.

The generated flow is:

```text
<interface>:80  -> Caddy:80
<interface>:443 -> Caddy:443
```

No destination NAT or port translation is created. This matches deployments where the public network interface is attached directly to OPNsense, including PCI passthrough.

## Scope

The module owns exactly:

- one HTTP pass rule;
- one HTTPS pass rule.

It does not manage Caddy global settings, Caddy domains or handlers, interface assignments, public DNS, Unbound records, or OPNsense WebUI settings. The WebUI must be moved away from ports 80 and 443 before Caddy is enabled. Use `modules/caddy-reverse-proxy` for individual proxy domains.

## Requirements

- OpenTofu 1.12 or newer;
- `biptec/opnsense` provider 0.26.0 or newer;
- Caddy installed in OPNsense;
- Caddy configured to listen on the same ports supplied to this module;
- an existing logical OPNsense ingress interface such as `wan`.

## Configure Caddy listeners

Caddy global settings are a singleton and must be imported before management:

```hcl
import {
  to = opnsense_caddy_settings.main
  id = "caddy_settings"
}

resource "opnsense_caddy_settings" "main" {
  enabled       = true
  http_port     = 80
  https_port    = 443
  run_as_user   = "root"
  http_versions = ["h1", "h2"]
}
```

## Create edge ingress

```hcl
module "caddy_ingress" {
  source = "./modules/caddy-edge-ingress"

  interface = "wan"
}
```

By default, the module matches `wanip`, permits ports 80 and 443, and accepts traffic from any source. Set `destination` when the rules must match a specific address or alias.

For a restricted ingress source:

```hcl
module "private_caddy_ingress" {
  source = "./modules/caddy-edge-ingress"

  interface      = "opt2"
  destination    = "PUBLIC_WEB_IP"
  source_network = "TRUSTED_PROXIES"
  sequence_base  = 300
}
```

## Security properties

- Rules are scoped to one logical interface.
- Only the configured HTTP and HTTPS destination ports are permitted.
- No loopback translation or hairpin NAT is created.
- Management WebUI exposure is outside this module and must remain limited to the management interface.
- The module is IPv4-only. IPv6 exposure requires a separate reviewed policy.
