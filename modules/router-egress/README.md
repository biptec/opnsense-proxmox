# Router egress module

This module owns the WAN identity used exclusively for translated outbound traffic. It does not configure DNS, Caddy, service loopbacks, ingress firewall rules, or workload interfaces.

The dedicated egress address is always created as a WAN `/32` IP Alias with `no_bind = true`. The module requires the primary WAN address/prefix and gateway and verifies that both the gateway and egress alias are on-link through that connected subnet. The egress alias is only an additional source identity; it does not create a second connected route.

`service_binding_guard` must come from the already-applied `router-services` module. This creates a Terraform dependency so exact NTP/BIND/Caddy bindings are configured before an additional WAN address appears. `no_bind = true` is still set on the egress VIP, but it is not treated as a universal socket-binding guarantee because individual daemons can enumerate interface addresses independently.

Outbound NAT is detached by default. A staged cutover first attaches the egress VIP, then enables the NAT block. When enabled, the module manages outbound NAT in `hybrid` mode, creates deterministic early NO-NAT rules for routed public subnets, and translates selected internal networks through the dedicated egress address.

The packet-level lab gate verified the intended topology with one `/26` primary WAN and three `/32` aliases: replies from service aliases preserved the exact destination identity, while traffic from an internal test network left WAN with the dedicated egress source address.

Example:

```hcl
module "router_egress" {
  source = "./modules/router-egress"

  wan_interface             = "wan"
  wan_primary_address       = "198.51.100.112"
  wan_primary_prefix        = 26
  wan_gateway               = "198.51.100.65"
  dedicated_egress_address  = "198.51.100.95"
  service_binding_guard     = module.router_services.service_binding_guard
  public_egress_vip_enabled = true
  outbound_nat_enabled      = true

  reserved_addresses = [
    "192.0.2.10",
    "198.51.100.88",
    "198.51.100.87",
    "10.53.0.2",
    "10.80.0.2",
    "10.123.0.2",
  ]

  internal_egress_networks = [
    "10.0.0.0/8",
    "172.16.0.0/12",
  ]

  routed_public_subnets = [
    "203.0.113.112/29",
  ]
}
```

Keep the egress NAT rule after the complete NO-NAT range. Removing the singleton NAT settings resource from state does not revert the OPNsense mode, so treat activation as a controlled platform cutover rather than a temporary toggle.
