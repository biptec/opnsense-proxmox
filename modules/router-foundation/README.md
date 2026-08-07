# Router foundation module

This module establishes the resources that must have exactly one owner in the router state:

- the `os-api-extensions` package;
- WebGUI/API and SSH listener bindings on one management interface;
- one reserved VLAN ID and one canonical IPv4 `/30` for every movable service;
- optional reserved IPv6 `/64` for dual-stack movable services;
- router-hosted service endpoints on dedicated loopbacks;
- externalized service VLANs where OPNsense owns the other usable IPv4 host and the service keeps its selected endpoint.

By default the IPv4 service endpoint is host `.2` and the future router side is `.1`. `service_ipv4_host = 1` explicitly supports inventories where those two usable IPv4 hosts are reversed, such as Mizar. While a service runs on OPNsense, its selected endpoint `/30` is assigned to a dedicated loopback and the reserved service VLAN is not created. During a later move, Terraform readdresses the same assignment to the reserved VLAN: OPNsense receives the other usable host and the service VM receives the unchanged endpoint. The same `/30` is therefore never connected to loopback and VLAN at the same time.

When `ipv6_subnet` is configured, the stable IPv6 service endpoint is `::2/64` and the future router side is `::1/64`. IPv4 host selection and IPv6 host selection are intentionally independent.

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
      vlan_id           = 210
      subnet            = "10.53.0.0/30"
      service_ipv4_host = 1
      ipv6_subnet       = "2001:db8:53::/64"
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

The management address is checked against every service `/30`. Service VLAN IDs, IPv4 `/30` networks, and configured IPv6 `/64` networks must be unique and cannot use an ID listed in `reserved_vlan_ids`.

Service endpoint assignments are protected by default. Set `allow_service_readdress = true` only for the reviewed migration between the local loopback endpoint and the reserved service VLAN router endpoint (or another intentional readdress), then return it to `false`. Moving a service off OPNsense is represented by `hosted_on_router = false`; that transition creates the reserved VLAN and changes the OPNsense side to the other usable IPv4 host while the service endpoint remains unchanged.
