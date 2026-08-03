# Caddy edge ingress module

Creates IPv4 destination NAT and firewall rules that expose Caddy on one OPNsense ingress interface while leaving the OPNsense WebUI on ports 80 and 443 for the management path.

The generated flow is:

```text
<interface>:80  -> 127.0.0.1:8080
<interface>:443 -> 127.0.0.1:8443
```

The target is intentionally fixed to loopback. The pass rules match the post-NAT loopback destination, so direct connections to the Caddy listener ports on the ingress interface remain blocked unless another rule explicitly permits them.

## Scope

The module owns exactly:

- one HTTP destination NAT rule;
- one HTTPS destination NAT rule;
- one HTTP pass rule;
- one HTTPS pass rule.

It does not manage Caddy global settings, Caddy domains or handlers, interface assignments, public DNS, Unbound records, or OPNsense WebUI settings. Use `modules/caddy-reverse-proxy` for individual proxy domains.

## Requirements

- OpenTofu 1.12 or newer;
- `biptec/opnsense` provider 0.26.0 or newer;
- Caddy installed in OPNsense;
- Caddy configured to listen on the same local ports supplied to this module;
- an existing logical OPNsense ingress interface such as `wan`.

## Configure Caddy listeners

Caddy global settings are a singleton and must be imported before management:

```hcl
locals {
  caddy_http_port  = 8080
  caddy_https_port = 8443
}

import {
  to = opnsense_caddy_settings.main
  id = "caddy_settings"
}

resource "opnsense_caddy_settings" "main" {
  enabled       = true
  http_port     = local.caddy_http_port
  https_port    = local.caddy_https_port
  run_as_user   = "root"
}
```

## Create edge ingress

```hcl
module "caddy_ingress" {
  source = "./modules/caddy-edge-ingress"

  interface        = "wan"
  caddy_http_port  = local.caddy_http_port
  caddy_https_port = local.caddy_https_port
}
```

By default, the module matches `wanip`, exposes ports 80 and 443, translates them to 8080 and 8443, disables NAT reflection, and accepts traffic from any source. Set `destination` when the rule must match a specific public address or alias.

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

- NAT is scoped to the selected interface, so management-interface requests continue to reach the OPNsense WebUI.
- Public requests on ports 80 and 443 are translated before they can reach lighttpd.
- Direct ingress-interface access to 8080 and 8443 is not permitted by these rules.
- Caddy listener ports cannot be 80 or 443 and all four external/internal ports must be distinct.
- The module is IPv4-only. IPv6 exposure requires a separate reviewed policy rather than silently reusing IPv4 NAT assumptions.
- NAT reflection defaults to disabled. Internal clients should use appropriate internal DNS records rather than hairpin NAT.

The rule shape was verified on OPNsense 26.7.1: PF generated interface-scoped `rdr` rules to `127.0.0.1:8080` and `127.0.0.1:8443`, HTTPS reached the Caddy upstream, the WebUI remained available on the management address, and direct access to the Caddy listener ports from the ingress network timed out.
