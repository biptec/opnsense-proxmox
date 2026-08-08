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
  management_ipv4_address  = "10.0.0.2"
  management_web_ipv4_cidr = "10.0.0.6/30"
  management_ssh_ipv6_cidr = "2001:db8:1::2/64"
  management_web_ipv6_cidr = "2001:db8:2::2/64"
  webgui_certificate_ref   = "test-certificate-ref"

  wan = {
    vlan_id                  = 3801
    primary_address          = "198.51.100.112"
    primary_prefix           = 26
    gateway                  = "198.51.100.65"
    public_caddy_address     = "198.51.100.87"
    public_dns_address       = "198.51.100.88"
    dedicated_egress_address = "198.51.100.95"
  }

  routed_networks = {
    svc_vela = {
      vlan_id        = 2817
      subnet         = "10.16.26.0/30"
      router_address = "10.16.26.1"
      description    = "Vela VPN"
    }
    public = {
      vlan_id        = 3802
      subnet         = "203.0.113.112/29"
      router_address = "203.0.113.113"
      description    = "Routed public transport"
    }
  }

  service_networks = {
    dns   = { vlan_id = 2803, subnet = "10.16.16.52/30", service_ipv4_host = 1, ipv6_subnet = "2001:db8:53::/64" }
    ntp   = { vlan_id = 2819, subnet = "10.16.16.120/30", ipv6_subnet = "2001:db8:123::/64" }
    caddy = { vlan_id = 2821, subnet = "10.16.16.80/30", ipv6_subnet = "2001:db8:80::/64" }
    nat   = { vlan_id = 2822, subnet = "10.16.16.92/30", ipv6_subnet = "2001:db8:92::/64" }
  }

  routed_public_subnets = ["203.0.113.112/29"]
  vpn_client_route = {
    network         = "10.198.0.0/24"
    via_network_key = "svc_vela"
    gateway_address = "10.16.26.2"
  }
}

run "safe_platform_composition" {
  command = plan

  assert {
    condition = (
      opnsense_interfaces_vlan.wan.tag == 3801 &&
      opnsense_interfaces_assignment.wan.ipv4.address == "198.51.100.112" &&
      opnsense_interfaces_assignment.wan.ipv4.prefix == 26 &&
      opnsense_routing_gateway.wan.gateway == "198.51.100.65"
    )
    error_message = "WAN must be VLAN 3801 with the approved primary address and on-link gateway."
  }

  assert {
    condition = (
      length(opnsense_interfaces_vlan.routed) == 2 &&
      opnsense_interfaces_vlan.routed["svc_vela"].tag == 2817 &&
      opnsense_route.vpn_clients.network == "10.198.0.0/24"
    )
    error_message = "Routed VLANs and the VPN client route must be composed in the shared router state."
  }

  assert {
    condition = (
      length(opnsense_interfaces_vip.management) == 3 &&
      output.service_addresses["dns"] == "10.16.16.53" &&
      output.service_ipv6_addresses["caddy"] == "2001:db8:80::2"
    )
    error_message = "Management aliases and portable dual-stack service identities must be deterministic."
  }

  assert {
    condition = (
      output.public_dns_address == "198.51.100.88" &&
      output.public_caddy_address == "198.51.100.87" &&
      output.dedicated_egress_address == "198.51.100.95"
    )
    error_message = "Public DNS, Caddy, and Source NAT identities must remain separate."
  }

  assert {
    condition = (
      module.router_services.public_dns_vip_id == null &&
      module.router_services.public_caddy_vip_id == null &&
      module.router_egress.dedicated_egress_vip_id == null &&
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
      opnsense_bind_record.public_ns_ipv4.value == "198.51.100.88"
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
      opnsense_firewall_filter.platform_ipv4["management_ssh"].enabled &&
      opnsense_firewall_filter.platform_ipv4["management_web"].enabled &&
      !opnsense_firewall_filter.platform_ipv4["block_web_on_ssh_identity"].enabled &&
      !opnsense_firewall_filter.platform_ipv4["internal_internet_egress"].enabled
    )
    error_message = "Safe defaults must retain Unbound and keep DNS ingress, management cross-blocking, and Internet egress detached."
  }

  assert {
    condition = (
      contains(opnsense_firewall_filter.platform_ipv4["management_ssh"].interface.interface, "lan") &&
      contains(opnsense_firewall_filter.platform_ipv4["management_ssh"].interface.interface, "opt10") &&
      contains(opnsense_firewall_filter.platform_ipv4["management_web"].interface.interface, "opt10") &&
      contains(opnsense_firewall_filter.platform_ipv4["block_web_on_ssh_identity"].interface.interface, "opt10") &&
      contains(opnsense_firewall_filter.platform_ipv4["block_ssh_on_web_identity"].interface.interface, "opt10") &&
      contains(opnsense_firewall_filter.platform_ipv6["management_ssh_ipv6"].interface.interface, "opt10") &&
      contains(opnsense_firewall_filter.platform_ipv6["management_web_ipv6"].interface.interface, "opt10") &&
      contains(opnsense_firewall_filter.platform_ipv6["block_web_on_ssh_ipv6"].interface.interface, "opt10") &&
      contains(opnsense_firewall_filter.platform_ipv6["block_ssh_on_web_ipv6"].interface.interface, "opt10")
    )
    error_message = "Management endpoint allow/block policy must apply on routed internal ingress as well as the direct management NIC."
  }
}

run "reject_duplicate_platform_vlan" {
  command = plan

  variables {
    routed_networks = {
      svc_vela = {
        vlan_id        = 3801
        subnet         = "10.16.26.0/30"
        router_address = "10.16.26.1"
        description    = "Vela VPN"
      }
      public = {
        vlan_id        = 3802
        subnet         = "203.0.113.112/29"
        router_address = "203.0.113.113"
        description    = "Routed public transport"
      }
    }
  }

  expect_failures = [terraform_data.platform_contract]
}

run "reject_vpn_gateway_outside_selected_vlan" {
  command = plan

  variables {
    vpn_client_route = {
      network         = "10.198.0.0/24"
      via_network_key = "svc_vela"
      gateway_address = "10.16.27.2"
    }
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
      opnsense_dns_service_cutover.primary.target == "bind" &&
      opnsense_dns_service_cutover.primary.allow_cutover &&
      opnsense_firewall_filter.platform_ipv4["internal_dns_tcp"].enabled &&
      opnsense_firewall_filter.platform_ipv4["internal_dns_udp"].enabled &&
      opnsense_firewall_filter.platform_ipv4["public_dns_tcp"].enabled &&
      opnsense_firewall_filter.platform_ipv4["public_dns_udp"].enabled
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

run "secondary_dns_detach_retains_tsig" {
  command = plan

  variables {
    secondary_dns = {
      enabled = false
    }
    secondary_transfer_tsig_secret = "/////w=="
  }

  assert {
    condition = (
      length(opnsense_bind_tsig_key.secondary_transfer) == 1 &&
      opnsense_bind_primary_domain.internal.transfer_key_id == "" &&
      opnsense_bind_primary_domain.public.transfer_key_id == "" &&
      length(opnsense_bind_record.internal_ns2) == 0 &&
      length(opnsense_bind_record.public_ns2) == 0 &&
      length(opnsense_bind_primary_domain.internal.also_notify) == 0 &&
      length(opnsense_bind_primary_domain.public.also_notify) == 0
    )
    error_message = "Secondary detach must remove zone references before the supplied TSIG key is eligible for cleanup."
  }
}

run "reject_invalid_retained_tsig_secret" {
  command = plan

  variables {
    secondary_transfer_tsig_secret = "not-base64"
  }

  expect_failures = [terraform_data.platform_contract]
}

run "secondary_dns_integration" {
  command = plan

  variables {
    routed_networks = {
      host_rigi  = { vlan_id = 508, subnet = "10.16.222.0/30", router_address = "10.16.222.1", description = "Rigi management" }
      svc_alcor  = { vlan_id = 2804, subnet = "10.16.18.52/30", router_address = "10.16.18.54", description = "Alcor DNS2" }
      svc_kochab = { vlan_id = 2820, subnet = "10.16.18.120/30", router_address = "10.16.18.121", description = "Kochab NTP2" }
      svc_vela   = { vlan_id = 2817, subnet = "10.16.26.0/30", router_address = "10.16.26.1", description = "Vela VPN" }
      public     = { vlan_id = 3802, subnet = "203.0.113.112/29", router_address = "203.0.113.113", description = "Routed public" }
    }

    secondary_dns = {
      enabled           = true
      management_ipv4   = "10.16.222.2"
      internal_dns_ipv4 = "10.16.18.53"
      internal_dns_ipv6 = "2001:db8:1234::2"
      internal_ntp_ipv4 = "10.16.18.122"
      internal_ntp_ipv6 = "2001:db8:1278::2"
      public_dns_ipv4   = "203.0.113.114"
    }
    secondary_transfer_tsig_secret = "/////w=="
    cutover = {
      dns_target        = "bind"
      allow_dns_cutover = true
      public_dns_vip    = true
      ntp_serving       = true
    }
  }

  assert {
    condition = (
      length(opnsense_bind_tsig_key.secondary_transfer) == 1 &&
      opnsense_bind_primary_domain.internal.transfer_key_id == opnsense_bind_tsig_key.secondary_transfer[0].id &&
      opnsense_bind_primary_domain.internal.also_notify == toset(["10.16.18.53"]) &&
      opnsense_bind_primary_domain.public.also_notify == toset(["203.0.113.114"])
    )
    error_message = "Primary views must authenticate transfers and NOTIFY the matching Rigi identity."
  }

  assert {
    condition = (
      opnsense_bind_record.internal_ns2_ipv4[0].value == "10.16.18.53" &&
      opnsense_bind_record.public_ns2_ipv4[0].value == "203.0.113.114" &&
      opnsense_firewall_filter.platform_ipv4["public_dns2_tcp"].enabled &&
      opnsense_firewall_filter.platform_ipv4["public_dns2_udp"].enabled &&
      opnsense_firewall_filter.platform_ipv4["rigi_internal_ntp"].enabled &&
      opnsense_firewall_filter.platform_ipv4["rigi_public_egress"].enabled
    )
    error_message = "Secondary enablement must publish NS2, allow public DNS2, internal NTP2, and routed-public egress."
  }
}
