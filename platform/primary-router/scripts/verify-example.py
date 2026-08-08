#!/usr/bin/env python3
import json
import os
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
expression = '''jsonencode({
  management_ssh = var.management_ssh_ipv4_cidr
  management_web  = var.management_web_ipv4_cidr
  wan             = var.wan
  routed          = var.routed_public_networks
  services        = var.service_networks
  egress          = var.internal_egress_networks
  routed_public   = [for network in values(var.routed_public_networks) : network.subnet]
})
'''
env = os.environ.copy()
env.update({
    "OPNSENSE_URI": "https://127.0.0.1",
    "OPNSENSE_API_KEY": "test",
    "OPNSENSE_API_SECRET": "test",
    "OPNSENSE_ALLOW_INSECURE": "true",
})
result = subprocess.run(
    ["tofu", "console", "-var-file=terraform.tfvars.example"],
    cwd=root,
    env=env,
    input=expression,
    text=True,
    capture_output=True,
    check=True,
)
# Console renders the jsonencode() result as one quoted HCL string.
payload = json.loads(json.loads(result.stdout.strip()))

assert payload["management_ssh"] == "10.16.214.2/30"
assert payload["management_web"] == "10.16.214.6/30"
assert payload["wan"] == {
    "vlan_id": 3801,
    "primary_cidr": "138.201.128.112/26",
    "gateway": "138.201.128.65",
    "public_proxy_address": "138.201.128.87",
    "public_dns_address": "138.201.128.88",
    "dedicated_egress_address": "138.201.128.95",
}

routed = payload["routed"]
assert len(routed) == 1
assert routed["public_transport"]["vlan_id"] == 3802
assert routed["public_transport"]["router_address"] == "5.9.227.113"

services = payload["services"]
assert set(services) == {"dns", "ntp", "proxy", "nat"}
assert services["dns"]["vlan_id"] == 2803 and services["dns"]["subnet"] == "10.16.16.52/30"
assert services["dns"]["service_ipv4_address"] == "10.16.16.53"
assert services["ntp"]["vlan_id"] == 2819 and services["ntp"]["subnet"] == "10.16.16.120/30"
assert services["proxy"]["vlan_id"] == 2821 and services["proxy"]["subnet"] == "10.16.16.80/30"
assert services["nat"]["vlan_id"] == 2822 and services["nat"]["subnet"] == "10.16.16.92/30"

assert payload["egress"] == ["10.0.0.0/8"]
assert payload["routed_public"] == ["5.9.227.112/29"]

print("primary-router-example=ok")
