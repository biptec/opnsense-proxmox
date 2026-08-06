# Router services module

This module owns the shared service listeners that run on the primary OPNsense router:

- opt-in public DNS and Caddy IP Alias addresses on WAN;
- BIND on the public DNS VIP and the internal DNS service address; IPv6 execution is disabled while `::1` remains as the required os-bind listener placeholder;
- Caddy on the public Caddy VIP and the internal Caddy `/30` address;
- NTP synchronization on the dedicated service interface, with client serving disabled by default;
- the `os-bind` and `os-caddy` packages;

The module leaves the BIND enabled flag unmanaged by default so the DNS cutover layer can be its only owner. The pinned image must start with BIND disabled; set `bind_enabled = false` only for an explicit one-time bootstrap. Caddy remains disabled by default. NTP stays enabled for router clock synchronization, but serving clients requires `ntp_serve_clients = true`.

Public WAN aliases are detached by default. This is especially important for DNS: the active legacy Unbound resolver normally has wildcard port-53 sockets, so attaching the public DNS address before the guarded cutover would immediately make that address a local Unbound destination even while BIND stays disabled. Set `public_dns_vip_enabled = true` only in the staged DNS cutover where ingress policy and service ownership are ordered together. Likewise set `public_caddy_vip_enabled = true` only when Caddy configuration and ingress policy are ready. The module refuses `bind_enabled = true` or `caddy_enabled = true` while the corresponding public VIP remains detached.

OPNsense `ntpd` binds every address on the selected service interface. While NTP is router-hosted, that means both the permanent `.1` gateway and the portable `.2` service alias have local UDP/123 sockets. Keep `ntp_serve_clients = false` until ingress firewall policy permits UDP/123 only to the `.2` service address. After `.2` moves to a service VM, the router can keep using `.1` for its own clock synchronization without retaining the portable service address.

The module also does not disable Unbound or dnsmasq. That cutover belongs to the later DNS layer, where views and zones can be created before port 53 changes ownership.

The module intentionally does not create firewall rules. Packets to router-hosted service VIPs enter through WAN or a client VLAN, so pass rules belong to those ingress interfaces. The dedicated service VLAN remains the stable migration segment and is not treated as the source interface for client traffic.

```hcl
module "router_services" {
  source = "./modules/router-services"

  wan_interface            = "wan"
  management_address       = module.router_foundation.management_address
  wan_primary_address      = "192.0.2.10"
  api_extensions_plugin_id = module.router_foundation.api_extensions_plugin_id
  public_dns_address       = "198.51.100.53"
  public_caddy_address     = "198.51.100.80"

  service_addresses  = module.router_foundation.service_addresses
  service_interfaces = module.router_foundation.service_interfaces

  ntp_servers = [
    {
      host   = "0.pool.ntp.org"
      pool   = true
      iburst = true
      prefer = true
    }
  ]

  caddy_acme_email = "operations@example.net"
}
```

BIND and Caddy settings are existing singleton objects in OPNsense. Import them declaratively from the root configuration before the first apply:

```hcl
import {
  to = module.router_services.opnsense_bind_settings.main
  id = "bind_settings"
}

import {
  to = module.router_services.opnsense_caddy_settings.main
  id = "caddy_settings"
}
```

Keep these import blocks in configuration; repeated plans remain idempotent after the objects are in state. The pinned OPNsense image must already contain `os-bind` and `os-caddy`, because their singleton APIs are read during the import phase before Terraform can create package resources. The package resources then adopt the installed packages and verify their lifecycle without uninstalling them on state removal.
