# Application-owned Caddy routes

This example represents a separate application or server repository. It assumes that the router platform repository has already prepared OPNsense, moved the WebUI, created the internal CA, configured Caddy on ports 80 and 443, and installed the global firewall rules.

The example owns only application-level resources:

- Caddy domains;
- Caddy handlers;
- optional access lists;
- ACME, internal, or existing site certificates;
- optional Unbound host overrides.

It does not manage the VM, API credentials, WebUI, internal CA, global Caddy settings, ingress firewall, interfaces, public DNS, or upstream workloads.

## Route map

Every entry in `routes` is keyed by its frontend FQDN and declares one or more upstreams:

```hcl
routes = {
  "www.example.com" = {
    upstream_domains = ["10.20.0.10"]
    upstream_port    = 8080
    certificate_mode = "acme"
  }
}
```
For an internal route, set `certificate_mode = "internal"`, provide the existing CA name, and optionally create a split-DNS record:

```hcl
"service.internal.example.com" = {
  upstream_domains  = ["10.20.0.20"]
  upstream_port     = 8443
  upstream_protocol = "https"
  certificate_mode  = "internal"
  internal_ca_name  = "internal.example.com"
  allowed_networks  = ["10.0.0.0/8"]
  unbound_address   = "10.40.0.10"
}
```

## Credentials

Load the credentials file created by the router platform deployment and export its values only to the provider process. Keep the values out of HCL and state. The provider should also receive `SSL_CERT_FILE` pointing to the exported router CA certificate.

## Apply

```sh
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu plan
tofu apply
```

Public DNS must already resolve to the router. Unbound records are created only for routes with `unbound_address`.
