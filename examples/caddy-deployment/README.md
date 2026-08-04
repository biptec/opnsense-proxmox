# Caddy deployment example

This root configuration composes the reusable Caddy modules into two isolated ingress paths:

```text
public interface:80/443       -> Caddy 8080/8443 -> public upstream
internal service IP:80/443    -> Caddy 8080/8443 -> internal upstream
management interface:80/443   -> OPNsense WebUI
```

Public DNS remains outside OpenTofu. Unbound manages only the internal split-DNS record.

## Required existing infrastructure

- OPNsense with `os-caddy` installed;
- a management interface used for the WebUI;
- a different public ingress interface;
- a different internal service interface;
- a dedicated IPv4 address or VIP on the internal service interface;
- an existing OPNsense CA for internal certificates;
- reachable public and internal upstream services.

The dedicated internal service address must not be the management address. This example intentionally does not create interface assignments or virtual IPs because those lifecycles belong to the network deployment layer.

## Ownership

This configuration manages:

- the imported Caddy settings singleton;
- public and internal interface-scoped DNAT and pass rules;
- one public Caddy domain with ACME;
- one internal Caddy domain and leaf certificate issued by the existing CA;
- one Unbound A record pointing the internal FQDN to the dedicated service address.

It does not manage public DNS, the internal CA, interface assignments, virtual IPs, upstream workloads, or the OPNsense WebUI.

## Credentials

Keep API credentials outside files and state:

```sh
export OPNSENSE_URI="https://router.example.com"
export OPNSENSE_API_KEY="<api key>"
export OPNSENSE_API_SECRET="<api secret>"
```

Use `OPNSENSE_ALLOW_INSECURE=true` only in an isolated laboratory.

## Apply

Copy the non-secret example values and review them:

```sh
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu plan
tofu apply
```

The import block adopts the existing Caddy settings singleton with ID `caddy_settings`. The first plan must show an import rather than an attempt to create a second settings object. Keep `import_caddy_settings = true`; the false value exists only for mock-provider tests because OpenTofu testing does not support import operations.

Before applying, ensure the public FQDN resolves to the public ingress address. The internal FQDN is created in Unbound during apply and resolves to `internal_service_address`.

NAT reflection is disabled on both paths. Internal clients use split DNS instead of hairpinning through the public address.

## Destroy behavior

Destroy removes the Caddy domains, generated internal leaf certificate, Unbound record, and both ingress rule sets. The imported Caddy settings resource is removed from state only; OPNsense settings remain unchanged. Change or disable the settings explicitly before destroy when the service must be stopped as part of decommissioning.
