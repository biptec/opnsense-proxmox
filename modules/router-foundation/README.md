# Router foundation module

This module establishes the resources that must have exactly one owner in the router state:

- the `os-api-extensions` package;
- WebGUI/API and SSH listener bindings on one management interface;
- one reserved VLAN ID and one canonical IPv4 `/30` for every movable service;
- router-hosted `.2/30` endpoints on dedicated loopbacks;
- externalized service VLANs where OPNsense owns `.1/30` and the service VM owns the unchanged `.2/30`.

A service keeps the same host `.2` address throughout its lifetime. While it runs on OPNsense, `.2/30` is assigned to a dedicated loopback and the reserved service VLAN is not created. During a later move, Terraform readdresses the same assignment to the reserved VLAN: OPNsense receives `.1/30` and the service VM receives the unchanged `.2/30`. The same `/30` is therefore never connected to loopback and VLAN at the same time.

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

Do not declare the same WebGUI, SSH, loopback/VLAN assignment, or service address in another state.

The first apply that changes WebGUI/API or SSH listener ownership requires `allow_management_readdress = true` and a working console or alternate management path. Set it back to `false` after the listener cutover succeeds.

OPNsense SSH binding is interface-based: it generates `ListenAddress` entries for every bindable address on the selected interface. The management interface must therefore remain dedicated and carry only the intended management address. This module never places service endpoints on that interface; public VIPs must be owned by the WAN/ingress layer.

The management address is checked against every service `/30`. Service VLAN IDs and `/30` networks must be unique and cannot use an ID listed in `reserved_vlan_ids`.

Service endpoint assignments are protected by default. Set `allow_service_readdress = true` only for the reviewed migration between local loopback `.2/30` and external service VLAN `.1/30` (or another intentional readdress), then return it to `false`. Moving a service off OPNsense is represented by `hosted_on_router = false`; that transition creates the reserved VLAN and changes the OPNsense side from `.2/30` on loopback to `.1/30` on the VLAN.
