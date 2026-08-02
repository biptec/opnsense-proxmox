# Caddy reverse proxy module

Creates one Caddy frontend domain and one reverse-proxy handler on OPNsense. It can optionally create an access list from explicitly supplied networks.

The module does not create public or internal DNS records. The caller must ensure that `domain` resolves appropriately before enabling public ACME issuance.

## Public service

```hcl
module "application_proxy" {
  source = "./modules/caddy-reverse-proxy"

  domain           = "application.example.com"
  upstream_domains = [module.application_vm.ipv4_address]
  upstream_port    = 8080
}
```

## Internal service

```hcl
module "internal_proxy" {
  source = "./modules/caddy-reverse-proxy"

  domain                              = "application.internal.example"
  upstream_domains                    = ["10.20.0.10"]
  upstream_port                       = 8443
  upstream_protocol                   = "https"
  certificate_mode                    = "internal"
  internal_ca_name                    = "internal.example"
  internal_certificate_lifetime_days = 3650
  allowed_networks                    = ["10.0.0.0/24", "10.10.0.0/24"]
  upstream_tls_ca_ref_id              = var.internal_ca_ref_id
  upstream_tls_server_name            = "backend.internal.example"
}
```
