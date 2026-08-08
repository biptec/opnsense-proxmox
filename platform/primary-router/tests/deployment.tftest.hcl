mock_provider "opnsense" {
  mock_resource "opnsense_interfaces_vlan" {
    defaults = { id = "11111111-1111-4111-8111-111111111111" }
  }
  mock_resource "opnsense_interfaces_assignment" {
    defaults = { id = "opt10", name = "opt10" }
  }
  mock_resource "opnsense_interfaces_loopback" {
    defaults = { id = "22222222-2222-4222-8222-222222222222", device_id = 10 }
  }
  mock_resource "opnsense_interfaces_vip" {
    defaults = { id = "33333333-3333-4333-8333-333333333333", address = "198.51.100.1" }
  }
  mock_resource "opnsense_routing_gateway" {
    defaults = { id = "44444444-4444-4444-8444-444444444444" }
  }
  mock_resource "opnsense_bind_acl" {
    defaults = { id = "55555555-5555-4555-8555-555555555555" }
  }
  mock_resource "opnsense_bind_view" {
    defaults = { id = "66666666-6666-4666-8666-666666666666" }
  }
  mock_resource "opnsense_bind_primary_domain" {
    defaults = { id = "77777777-7777-4777-8777-777777777777" }
  }
  mock_resource "opnsense_bind_record" {
    defaults = { id = "88888888-8888-4888-8888-888888888888" }
  }
  mock_resource "opnsense_bind_tsig_key" {
    defaults = { id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" }
  }
  mock_resource "opnsense_firewall_alias" {
    defaults = { id = "99999999-9999-4999-8999-999999999999" }
  }
  mock_resource "opnsense_firewall_filter" {
    defaults = { id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }
  }
}

variables {
  management_ssh_ipv4_cidr = "10.0.0.2/30"
  management_web_ipv4_cidr = "10.0.0.6/30"
  management_ssh_ipv6_cidr = "2001:db8:1::2/64"
  management_web_ipv6_cidr = "2001:db8:2::2/64"
  webgui_certificate_ref   = "test-certificate-ref"

  wan = {
    vlan_id                       = 3801
    primary_cidr                  = "198.51.100.112/26"
    gateway                       = "198.51.100.65"
    primary_ipv6_cidr             = "2001:db8:ffff::112/64"
    ipv6_gateway                  = "fe80::1"
    public_proxy_address          = "198.51.100.87"
    public_proxy_ipv6_address     = "2001:db8:ffff::87"
    public_dns_address            = "198.51.100.88"
    public_dns_ipv6_address       = "2001:db8:ffff::88"
    dedicated_egress_address      = "198.51.100.95"
    dedicated_egress_ipv6_address = "2001:db8:ffff::95"
  }

  routed_public_networks = {
    public_transport = {
      vlan_id             = 3802
      subnet              = "203.0.113.112/29"
      router_address      = "203.0.113.113"
      ipv6_subnet         = "2001:db8:200::/64"
      router_ipv6_address = "2001:db8:200::113"
      description         = "Routed public transport"
    }
  }

  service_networks = {
    dns   = { vlan_id = 2803, subnet = "10.16.16.52/30", service_ipv4_address = "10.16.16.53", ipv6_subnet = "2001:db8:53::/64" }
    ntp   = { vlan_id = 2819, subnet = "10.16.16.120/30", service_ipv4_address = "10.16.16.122", ipv6_subnet = "2001:db8:123::/64" }
    proxy = { vlan_id = 2821, subnet = "10.16.16.80/30", service_ipv4_address = "10.16.16.82", ipv6_subnet = "2001:db8:80::/64" }
    nat   = { vlan_id = 2822, subnet = "10.16.16.92/30", service_ipv4_address = "10.16.16.94", ipv6_subnet = "2001:db8:92::/64" }
  }

  trusted_internal_networks     = ["10.0.0.0/8", "2001:db8::/32"]
  internal_egress_ipv6_networks = ["2001:db8::/32"]
}

run "safe_platform_composition" {
  command = plan

  assert {
    condition = (
      opnsense_interfaces_vlan.wan.tag == 3801 &&
      opnsense_interfaces_assignment.wan.ipv4.address == "198.51.100.112" &&
      opnsense_interfaces_assignment.wan.ipv4.prefix == 26 &&
      opnsense_interfaces_assignment.wan.ipv6.address == "2001:db8:ffff::112" &&
      opnsense_interfaces_assignment.wan.ipv6.prefix == 64 &&
      opnsense_routing_gateway.wan.gateway == "198.51.100.65" &&
      opnsense_routing_gateway.wan_ipv6.gateway == "fe80::1" &&
      opnsense_routing_gateway.wan_ipv6.ip_protocol == "inet6"
    )
    error_message = "WAN must be VLAN 3801 with the approved primary address and on-link gateway."
  }

  assert {
    condition = (
      length(opnsense_interfaces_vlan.routed) == 1 &&
      opnsense_interfaces_vlan.routed["public_transport"].tag == 3802 &&
      opnsense_interfaces_assignment.routed["public_transport"].ipv6.address == "2001:db8:200::113" &&
      opnsense_interfaces_assignment.routed["public_transport"].ipv6.prefix == 64
    )
    error_message = "Primary router state must own only shared routed transport, not downstream service VLANs."
  }

  assert {
    condition = (
      length(opnsense_interfaces_vip.management) == 3 &&
      output.service_addresses["dns"] == "10.16.16.53" &&
      output.service_ipv6_addresses["proxy"] == "2001:db8:80::2"
    )
    error_message = "Management aliases and portable dual-stack service identities must be deterministic."
  }

  assert {
    condition = (
      output.dns_zone_name == "biptec.net" &&
      output.trusted_internal_networks == toset(["10.0.0.0/8", "2001:db8::/32"]) &&
      output.public_dns_address == "198.51.100.88" &&
      output.public_dns_ipv6_address == "2001:db8:ffff::88" &&
      output.public_proxy_address == "198.51.100.87" &&
      output.public_proxy_ipv6_address == "2001:db8:ffff::87" &&
      output.dedicated_egress_address == "198.51.100.95" &&
      output.dedicated_egress_ipv6_address == "2001:db8:ffff::95"
    )
    error_message = "Public DNS, reverse-proxy, and Source NAT identities must remain separate."
  }

  assert {
    condition = (
      output.downstream_router_contract.trunk_parent_device == "vtnet1" &&
      output.downstream_router_contract.wan_interface == "opt10" &&
      output.downstream_router_contract.routed_interfaces["public_transport"] == "opt10" &&
      output.downstream_router_contract.routed_public_networks["public_transport"].subnet == "203.0.113.112/29" &&
      output.downstream_router_contract.routed_public_networks["public_transport"].ipv6_subnet == "2001:db8:200::/64" &&
      output.downstream_router_contract.internal_dns_ipv4 == "10.16.16.53" &&
      output.downstream_router_contract.public_dns_ipv4 == "198.51.100.88" &&
      output.downstream_router_contract.public_dns_ipv6 == "2001:db8:ffff::88"
    )
    error_message = "The generic downstream contract must export primary-owned references without embedding downstream-specific data."
  }

  assert {
    condition = (
      module.router_services.public_dns_vip_id == null &&
      module.router_services.public_dns_ipv6_vip_id == null &&
      module.router_services.public_caddy_vip_id == null &&
      module.router_services.public_caddy_ipv6_vip_id == null &&
      module.router_egress.dedicated_egress_vip_id == null &&
      module.router_egress.dedicated_egress_ipv6_vip_id == null &&
      !module.router_egress.outbound_nat_enabled
    )
    error_message = "The composition must remain detached from public cutover by default."
  }

  assert {
    condition = (
      opnsense_bind_view.internal.recursion &&
      !opnsense_bind_view.internal.match_any &&
      opnsense_bind_view.public.match_any &&
      !opnsense_bind_view.public.recursion &&
      opnsense_bind_primary_domain.internal.dnssec &&
      opnsense_bind_primary_domain.public.dnssec &&
      opnsense_bind_record.internal_ns_ipv4.value == "10.16.16.53" &&
      opnsense_bind_record.public_ns_ipv4.value == "198.51.100.88" &&
      opnsense_bind_record.public_ns_ipv6.value == "2001:db8:ffff::88"
    )
    error_message = "Internal/public BIND views and split primary NS records must follow the platform DNS contract."
  }

  assert {
    condition = (
      length(opnsense_bind_acl.internal_clients.name) <= 32 &&
      length(opnsense_bind_acl.internal_dns_destination.name) <= 32 &&
      length(opnsense_bind_acl.public_dns_destination.name) <= 32
    )
    error_message = "BIND ACL names must stay within the os-bind 32-character backend limit."
  }

  assert {
    condition = (
      opnsense_dns_service_cutover.primary.target == "unbound" &&
      !opnsense_dns_service_cutover.primary.allow_cutover &&
      !opnsense_firewall_filter.platform_ipv4["public_dns_tcp"].enabled &&
      !opnsense_firewall_filter.platform_ipv4["public_dns_udp"].enabled &&
      !opnsense_firewall_filter.platform_ipv6["public_dns_tcp_ipv6"].enabled &&
      !opnsense_firewall_filter.platform_ipv6["public_dns_udp_ipv6"].enabled &&
      opnsense_firewall_filter.platform_ipv4["management_ssh"].enabled &&
      opnsense_firewall_filter.platform_ipv4["management_web"].enabled &&
      !opnsense_firewall_filter.platform_ipv4["block_web_on_ssh_identity"].enabled
    )
    error_message = "Safe defaults must retain Unbound and keep DNS ingress, management cross-blocking, and Internet egress detached."
  }

  assert {
    condition = (
      opnsense_firewall_filter.platform_ipv4["management_ssh"].interface.invert &&
      opnsense_firewall_filter.platform_ipv4["management_ssh"].interface.interface == toset(["opt10"]) &&
      opnsense_firewall_filter.platform_ipv4["internal_dns_tcp"].interface.invert &&
      opnsense_firewall_filter.platform_ipv6["management_ssh_ipv6"].interface.invert &&
      opnsense_firewall_filter.platform_ipv6["management_ssh_ipv6"].filter.source.net == opnsense_firewall_alias.internal_ipv6.name &&
      opnsense_firewall_filter.platform_ipv6["management_web_ipv6"].interface.interface == toset(["opt10"])
    )
    error_message = "Primary internal-service policy must apply on all present and future downstream ingress interfaces while explicitly excluding WAN."
  }
}

run "reject_duplicate_platform_vlan" {
  command = plan

  variables {
    routed_public_networks = {
      public = {
        vlan_id        = 3801
        subnet         = "203.0.113.112/29"
        router_address = "203.0.113.113"
        description    = "Routed public transport"
      }
    }
  }

  expect_failures = [terraform_data.platform_contract]
}

run "reject_ipv6_endpoints_without_trusted_ipv6_scope" {
  command = plan

  variables {
    trusted_internal_networks = ["10.0.0.0/8"]
  }

  expect_failures = [terraform_data.platform_contract]
}

run "guarded_bind_cutover" {
  command = plan

  variables {
    cutover = {
      dns_target        = "bind"
      allow_dns_cutover = true
      public_dns_vip    = true
    }
  }

  assert {
    condition = (
      module.router_services.public_dns_vip_id != null &&
      module.router_services.public_dns_ipv6_vip_id != null &&
      opnsense_dns_service_cutover.primary.target == "bind" &&
      opnsense_dns_service_cutover.primary.allow_cutover &&
      opnsense_firewall_filter.platform_ipv4["internal_dns_tcp"].enabled &&
      opnsense_firewall_filter.platform_ipv4["internal_dns_udp"].enabled &&
      opnsense_firewall_filter.platform_ipv4["public_dns_tcp"].enabled &&
      opnsense_firewall_filter.platform_ipv4["public_dns_udp"].enabled &&
      opnsense_firewall_filter.platform_ipv6["public_dns_tcp_ipv6"].enabled &&
      opnsense_firewall_filter.platform_ipv6["public_dns_udp_ipv6"].enabled
    )
    error_message = "BIND cutover must attach the DNS VIP and activate only DNS-specific ingress policy."
  }
}

run "reject_bind_without_public_dns_vip" {
  command = plan

  variables {
    cutover = {
      dns_target        = "bind"
      allow_dns_cutover = true
      public_dns_vip    = false
    }
  }

  expect_failures = [terraform_data.platform_contract]
}

run "reject_public_dns_vip_while_unbound_owns_port" {
  command = plan

  variables {
    cutover = {
      dns_target     = "unbound"
      public_dns_vip = true
    }
  }

  expect_failures = [terraform_data.platform_contract]
}
