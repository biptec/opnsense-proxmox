# Router foundation module

This module establishes the resources that must have exactly one owner in the router state:

- the `os-api-extensions` package;
- WebGUI/API and SSH listener bindings on one management interface;
- one tagged VLAN and one canonical IPv4 `/30` for every movable service;
- permanent router gateway `.1/30` addresses;
- optional router-hosted service `.2/32` IP Alias addresses.

A service keeps the same host `.2` address throughout its lifetime. While it runs on OPNsense, `.2` is a bindable IP Alias on the service VLAN. During a later move, Terraform removes only that IP Alias and the service VM receives `.2/30`; OPNsense keeps `.1/30` as the gateway.

The module does not manage DNS zones, BIND, Caddy, NTP, firewall policy, public VIPs, NAT, or site-specific records. Those belong to later composition layers.

```hcl
module "router_foundation" {
  source = "./modules/router-foundation"

  management_interface = "lan"
  management_address   = "10.0.0.1"
  trunk_parent_device  = "vtnet1"
  reserved_vlan_ids    = [100] # for example, an existing WAN VLAN

  webgui = {
    certificate_ref         = "existing-certificate-reference"
    session_timeout_minutes = 15
  }

  service_networks = {
    dns = {
      vlan_id = 210
      subnet  = "10.53.0.0/30"
    }
    caddy = {
      vlan_id = 211
      subnet  = "10.80.0.0/30"
    }
    ntp = {
      vlan_id = 212
      subnet  = "10.123.0.0/30"
    }
  }
}
```

Do not declare the same WebGUI, SSH, VLAN, interface assignment, or service IP Alias in another state.

The first apply that changes WebGUI/API or SSH listener ownership requires `allow_management_readdress = true` and a working console or alternate management path. Set it back to `false` after the listener cutover succeeds.

The management address is checked against every service `/30`. Service VLAN IDs and `/30` networks must be unique and cannot use an ID listed in `reserved_vlan_ids`.

Permanent service gateway assignments are protected by default. Set `allow_service_readdress = true` only for a reviewed change to the VLAN device or `.1/30` gateway, then return it to `false`. Moving a service off OPNsense is represented by `hosted_on_router = false`; the `.1/30` assignment remains unchanged while the `.2/32` IP Alias is removed.
