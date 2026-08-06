mock_provider "opnsense" {
  mock_resource "opnsense_interfaces_vlan" {
    defaults = {
      id = "11111111-1111-4111-8111-111111111111"
    }
  }

  mock_resource "opnsense_interfaces_assignment" {
    defaults = {
      id   = "opt10"
      name = "opt10"
    }
  }

  mock_resource "opnsense_interfaces_vip" {
    defaults = {
      id      = "22222222-2222-4222-8222-222222222222"
      address = "10.53.0.2"
    }
  }
}

variables {
  management_interface = "lan"
  management_address   = "10.0.0.1"
  trunk_parent_device  = "vtnet1"
  reserved_vlan_ids    = [100, 101]
  webgui = {
    certificate_ref         = "management-certificate-ref"
    session_timeout_minutes = 15
  }
  service_networks = {
    dns = {
      vlan_id = 210
      subnet  = "10.53.0.0/30"
    }
    caddy = {
      vlan_id          = 211
      subnet           = "10.80.0.0/30"
      hosted_on_router = false
    }
    ntp = {
      vlan_id = 212
      subnet  = "10.123.0.0/30"
    }
  }
}

run "management_and_service_ownership" {
  command = plan

  assert {
    condition = (
      opnsense_plugin.api_extensions.name == "os-api-extensions" &&
      !opnsense_plugin.api_extensions.uninstall_on_destroy
    )
    error_message = "The API extensions package must be managed without uninstalling it on state removal."
  }

  assert {
    condition = (
      opnsense_system_webgui.management.interfaces == toset(["lan"]) &&
      opnsense_system_webgui.management.session_timeout_minutes == 15 &&
      !opnsense_system_webgui.management.allow_readdress &&
      opnsense_system_ssh.management.interfaces == toset(["lan"]) &&
      !opnsense_system_ssh.management.password_authentication &&
      !opnsense_system_ssh.management.permit_root_login
    )
    error_message = "WebGUI/API and SSH must be restricted to the management interface with safe defaults."
  }

  assert {
    condition = (
      opnsense_interfaces_vlan.service["dns"].parent == "vtnet1" &&
      opnsense_interfaces_vlan.service["dns"].tag == 210 &&
      opnsense_interfaces_vlan.service["dns"].protocol == "802.1q" &&
      opnsense_interfaces_vlan.service["dns"].device == "vlan210"
    )
    error_message = "Every service must receive a deterministic VLAN on the tagged trunk."
  }

  assert {
    condition = (
      opnsense_interfaces_assignment.service["dns"].device == "vlan210" &&
      opnsense_interfaces_assignment.service["dns"].ipv4.address == "10.53.0.1" &&
      opnsense_interfaces_assignment.service["dns"].ipv4.prefix == 30 &&
      opnsense_interfaces_assignment.service["dns"].ipv6.mode == "none" &&
      !opnsense_interfaces_assignment.service["dns"].allow_readdress
    )
    error_message = "The router must permanently own host .1 on the dedicated service VLAN."
  }

  assert {
    condition = (
      opnsense_interfaces_vip.service["dns"].network == "10.53.0.2/32" &&
      opnsense_interfaces_vip.service["dns"].interface == "opt10" &&
      !opnsense_interfaces_vip.service["dns"].no_bind &&
      opnsense_interfaces_vip.service["dns"].no_expand &&
      length(opnsense_interfaces_vip.service) == 2 &&
      !contains(keys(opnsense_interfaces_vip.service), "caddy")
    )
    error_message = "Only router-hosted services may hold their portable host .2 address as a bindable IP Alias."
  }

  assert {
    condition = (
      output.service_addresses["dns"] == "10.53.0.2" &&
      output.service_addresses["caddy"] == "10.80.0.2" &&
      output.router_addresses["dns"] == "10.53.0.1" &&
      output.service_interfaces["dns"] == "opt10" &&
      output.service_vlan_ids["dns"] == 210 &&
      output.service_vlan_devices["dns"] == "vlan210" &&
      output.router_hosted_service_addresses == {
        dns = "10.53.0.2"
        ntp = "10.123.0.2"
      }
    )
    error_message = "Router, portable service, interface, VLAN, and ownership outputs must be deterministic."
  }
}

run "reject_non_network_subnet" {
  command = plan

  variables {
    service_networks = {
      dns = {
        vlan_id = 210
        subnet  = "10.53.0.1/30"
      }
    }
  }

  expect_failures = [var.service_networks]
}

run "reject_non_30_subnet" {
  command = plan

  variables {
    service_networks = {
      dns = {
        vlan_id = 210
        subnet  = "10.53.0.0/29"
      }
    }
  }

  expect_failures = [var.service_networks]
}

run "reject_duplicate_subnets" {
  command = plan

  variables {
    service_networks = {
      dns = {
        vlan_id = 210
        subnet  = "10.53.0.0/30"
      }
      ntp = {
        vlan_id = 212
        subnet  = "10.53.0.0/30"
      }
    }
  }

  expect_failures = [var.service_networks]
}

run "reject_duplicate_vlan_ids" {
  command = plan

  variables {
    service_networks = {
      dns = {
        vlan_id = 210
        subnet  = "10.53.0.0/30"
      }
      ntp = {
        vlan_id = 210
        subnet  = "10.123.0.0/30"
      }
    }
  }

  expect_failures = [var.service_networks]
}

run "reject_reserved_vlan_id" {
  command = plan

  variables {
    service_networks = {
      dns = {
        vlan_id = 100
        subnet  = "10.53.0.0/30"
      }
    }
  }

  expect_failures = [var.service_networks]
}

run "reject_https_without_certificate" {
  command = plan

  variables {
    webgui = {
      protocol        = "https"
      certificate_ref = ""
    }
  }

  expect_failures = [var.webgui]
}

run "reject_management_service_overlap" {
  command = plan

  variables {
    management_address = "10.53.0.1"
  }

  expect_failures = [terraform_data.address_contract]
}

run "reject_invalid_management_interface" {
  command = plan

  variables {
    management_interface = "Management LAN"
  }

  expect_failures = [var.management_interface]
}

run "reject_invalid_trunk_device" {
  command = plan

  variables {
    trunk_parent_device = "Tagged Trunk"
  }

  expect_failures = [var.trunk_parent_device]
}

run "explicit_service_readdress_approval" {
  command = plan

  variables {
    allow_service_readdress = true
  }

  assert {
    condition     = opnsense_interfaces_assignment.service["dns"].allow_readdress
    error_message = "Permanent service gateway readdressing must require the explicit safety input."
  }
}
