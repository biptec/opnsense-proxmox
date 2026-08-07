mock_provider "opnsense" {
  mock_resource "opnsense_interfaces_vip" {
    defaults = {
      id      = "11111111-1111-4111-8111-111111111111"
      address = "198.51.100.95"
    }
  }
}

variables {
  wan_interface            = "wan"
  wan_primary_address      = "198.51.100.112"
  wan_primary_prefix       = 26
  wan_gateway              = "198.51.100.65"
  dedicated_egress_address = "198.51.100.95"
  service_binding_guard    = "router-services-applied"
  reserved_addresses       = ["192.0.2.10", "198.51.100.88", "198.51.100.87", "10.53.0.2"]
  internal_egress_networks = ["10.0.0.0/8", "172.16.0.0/12"]
  routed_public_subnets    = ["203.0.113.112/29"]
}

run "detached_by_default" {
  command = plan

  assert {
    condition = (
      length(opnsense_interfaces_vip.dedicated_egress) == 0 &&
      length(opnsense_firewall_nat_settings.outbound) == 0 &&
      length(opnsense_firewall_alias.internal_egress) == 0 &&
      length(opnsense_firewall_nat.routed_public_no_nat) == 0 &&
      length(opnsense_firewall_nat.dedicated_egress) == 0
    )
    error_message = "Egress VIP and NAT policy must remain detached by default."
  }
}

run "explicit_egress_vip" {
  command = plan

  variables {
    public_egress_vip_enabled = true
  }

  assert {
    condition = (
      opnsense_interfaces_vip.dedicated_egress[0].mode == "ipalias" &&
      opnsense_interfaces_vip.dedicated_egress[0].interface == "wan" &&
      opnsense_interfaces_vip.dedicated_egress[0].network == "198.51.100.95/32" &&
      opnsense_interfaces_vip.dedicated_egress[0].no_bind
    )
    error_message = "The dedicated egress identity must be a non-bindable WAN /32 IP Alias."
  }
}

run "outbound_nat_contract" {
  command = plan

  variables {
    public_egress_vip_enabled = true
    outbound_nat_enabled      = true
  }

  assert {
    condition     = opnsense_firewall_nat_settings.outbound[0].mode == "hybrid"
    error_message = "Explicit NO-NAT and dedicated egress rules require hybrid outbound NAT mode."
  }

  assert {
    condition = (
      opnsense_firewall_alias.internal_egress[0].name == "INTERNAL_EGRESS_NETWORKS" &&
      opnsense_firewall_alias.internal_egress[0].content == toset(["10.0.0.0/8", "172.16.0.0/12"])
    )
    error_message = "Internal egress networks must be represented by one explicit firewall alias."
  }

  assert {
    condition = (
      opnsense_firewall_nat.routed_public_no_nat["203.0.113.112/29"].disable_nat &&
      opnsense_firewall_nat.routed_public_no_nat["203.0.113.112/29"].sequence == 900000 &&
      opnsense_firewall_nat.routed_public_no_nat["203.0.113.112/29"].source.net == "203.0.113.112/29"
    )
    error_message = "Routed public workloads must bypass outbound NAT before translation rules."
  }

  assert {
    condition = (
      !opnsense_firewall_nat.dedicated_egress[0].disable_nat &&
      opnsense_firewall_nat.dedicated_egress[0].sequence == 910000 &&
      opnsense_firewall_nat.dedicated_egress[0].source.net == "INTERNAL_EGRESS_NETWORKS" &&
      opnsense_firewall_nat.dedicated_egress[0].target.ip == "198.51.100.95"
    )
    error_message = "Internal networks must translate through the dedicated egress address."
  }
}

run "reject_nat_without_vip" {
  command = plan

  variables {
    outbound_nat_enabled = true
  }

  expect_failures = [terraform_data.address_contract]
}

run "reject_nat_without_internal_networks" {
  command = plan

  variables {
    public_egress_vip_enabled = true
    outbound_nat_enabled      = true
    internal_egress_networks  = []
  }

  expect_failures = [terraform_data.address_contract]
}

run "reject_reused_egress_address" {
  command = plan

  variables {
    dedicated_egress_address = "198.51.100.88"
  }

  expect_failures = [terraform_data.address_contract]
}

run "reject_sequence_overlap" {
  command = plan

  variables {
    egress_nat_sequence = 900000
  }

  expect_failures = [terraform_data.address_contract]
}

run "reject_non_network_internal_egress" {
  command = plan

  variables {
    internal_egress_networks = ["10.0.0.1/8"]
  }

  expect_failures = [var.internal_egress_networks]
}

run "reject_non_network_routed_public" {
  command = plan

  variables {
    routed_public_subnets = ["203.0.113.113/29"]
  }

  expect_failures = [var.routed_public_subnets]
}

run "reject_offlink_gateway" {
  command = plan

  variables {
    wan_gateway = "203.0.113.1"
  }

  expect_failures = [terraform_data.address_contract]
}

run "reject_offlink_egress_alias" {
  command = plan

  variables {
    dedicated_egress_address = "203.0.113.95"
  }

  expect_failures = [terraform_data.address_contract]
}

run "reject_primary_wan_reuse" {
  command = plan

  variables {
    dedicated_egress_address = "198.51.100.112"
  }

  expect_failures = [terraform_data.address_contract]
}

run "reject_vip_without_service_binding_guard" {
  command = plan

  variables {
    public_egress_vip_enabled = true
    service_binding_guard     = ""
  }

  expect_failures = [terraform_data.address_contract]
}
