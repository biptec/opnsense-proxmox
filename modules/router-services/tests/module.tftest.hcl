mock_provider "opnsense" {
  mock_resource "opnsense_interfaces_vip" {
    defaults = {
      id      = "11111111-1111-4111-8111-111111111111"
      address = "198.51.100.1"
    }
  }
}

variables {
  wan_interface            = "wan"
  management_address       = "10.0.0.1"
  wan_primary_address      = "192.0.2.10"
  api_extensions_plugin_id = "os-api-extensions"
  public_dns_address       = "198.51.100.53"
  public_caddy_address     = "198.51.100.80"

  service_addresses = {
    dns   = "10.53.0.2"
    ntp   = "10.123.0.2"
    caddy = "10.80.0.2"
  }

  service_interfaces = {
    dns   = "lo10"
    ntp   = "lo11"
    caddy = "lo12"
  }

  bind_enabled = false

  ntp_servers = [
    {
      host   = "0.pool.ntp.org"
      pool   = true
      iburst = true
      prefer = true
    }
  ]
}

run "listener_ownership" {
  command = plan

  assert {
    condition = (
      length(opnsense_interfaces_vip.public_dns) == 0 &&
      length(opnsense_interfaces_vip.public_caddy) == 0
    )
    error_message = "Public DNS and Caddy VIPs must remain detached by default."
  }

  assert {
    condition = (
      !opnsense_bind_settings.main.enabled &&
      opnsense_bind_settings.main.port == 53 &&
      opnsense_bind_settings.main.disable_ipv6 &&
      opnsense_bind_settings.main.listen_ipv4 == toset(["198.51.100.53", "10.53.0.2"]) &&
      opnsense_bind_settings.main.listen_ipv6 == toset(["::1"])
    )
    error_message = "BIND must start disabled and own only its public and internal addresses."
  }

  assert {
    condition = (
      !opnsense_caddy_settings.main.enabled &&
      opnsense_caddy_settings.main.listen_addresses == toset(["198.51.100.80", "10.80.0.2"]) &&
      opnsense_caddy_settings.main.http_port == 80 &&
      opnsense_caddy_settings.main.https_port == 443
    )
    error_message = "Caddy must start disabled and own only its public and internal addresses."
  }

  assert {
    condition = (
      opnsense_ntp_settings.internal.enabled &&
      opnsense_ntp_settings.internal.interfaces == toset(["lo11"]) &&
      opnsense_ntp_settings.internal.kiss_of_death &&
      opnsense_ntp_settings.internal.rate_limiting &&
      opnsense_ntp_settings.internal.deny_modifications &&
      opnsense_ntp_settings.internal.disable_queries &&
      opnsense_ntp_settings.internal.disable_serving &&
      opnsense_ntp_settings.internal.deny_peer_associations &&
      opnsense_ntp_settings.internal.deny_trap_service
    )
    error_message = "NTP must serve only on its dedicated interface with hardened restrictions."
  }

  assert {
    condition = (
      opnsense_plugin.bind.name == "os-bind" &&
      opnsense_plugin.caddy.name == "os-caddy" &&
      !opnsense_plugin.bind.uninstall_on_destroy &&
      !opnsense_plugin.caddy.uninstall_on_destroy
    )
    error_message = "Service packages must remain installed when removed from Terraform state."
  }
}

run "explicit_public_vips" {
  command = plan

  variables {
    public_dns_vip_enabled   = true
    public_caddy_vip_enabled = true
  }

  assert {
    condition = (
      opnsense_interfaces_vip.public_dns[0].network == "198.51.100.53/32" &&
      !opnsense_interfaces_vip.public_dns[0].no_bind &&
      opnsense_interfaces_vip.public_caddy[0].network == "198.51.100.80/32" &&
      !opnsense_interfaces_vip.public_caddy[0].no_bind
    )
    error_message = "Explicit public VIP activation must create separate bindable WAN IP Aliases."
  }
}

run "reject_bind_enable_without_public_vip" {
  command = plan

  variables {
    bind_enabled = true
  }

  expect_failures = [terraform_data.listener_contract]
}

run "reject_caddy_enable_without_public_vip" {
  command = plan

  variables {
    caddy_enabled = true
  }

  expect_failures = [terraform_data.listener_contract]
}

run "explicit_ntp_serving" {
  command = plan

  variables {
    ntp_serve_clients = true
  }

  assert {
    condition     = !opnsense_ntp_settings.internal.disable_serving
    error_message = "NTP serving must require the explicit ntp_serve_clients input."
  }
}

run "reject_management_wan_identity_reuse" {
  command = plan

  variables {
    wan_primary_address = "10.0.0.1"
  }

  expect_failures = [terraform_data.listener_contract]
}

run "reject_management_address_reuse" {
  command = plan

  variables {
    public_dns_address = "10.0.0.1"
  }

  expect_failures = [terraform_data.listener_contract]
}

run "reject_wan_primary_address_reuse" {
  command = plan

  variables {
    public_caddy_address = "192.0.2.10"
  }

  expect_failures = [terraform_data.listener_contract]
}

run "reject_duplicate_listener_address" {
  command = plan

  variables {
    public_caddy_address = "198.51.100.53"
  }

  expect_failures = [terraform_data.listener_contract]
}

run "reject_public_internal_reuse" {
  command = plan

  variables {
    public_dns_address = "10.53.0.2"
  }

  expect_failures = [terraform_data.listener_contract]
}

run "reject_missing_api_extension_dependency" {
  command = plan

  variables {
    api_extensions_plugin_id = ""
  }

  expect_failures = [var.api_extensions_plugin_id]
}

run "reject_missing_service_address" {
  command = plan

  variables {
    service_addresses = {
      dns   = "10.53.0.2"
      caddy = "10.80.0.2"
    }
  }

  expect_failures = [var.service_addresses]
}

run "reject_invalid_service_address" {
  command = plan

  variables {
    service_addresses = {
      dns   = "10.53.0.2/30"
      ntp   = "10.123.0.2"
      caddy = "10.80.0.2"
    }
  }

  expect_failures = [var.service_addresses]
}

run "reject_missing_ntp_interface" {
  command = plan

  variables {
    service_interfaces = {
      dns   = "lo10"
      caddy = "lo12"
    }
  }

  expect_failures = [var.service_interfaces]
}
