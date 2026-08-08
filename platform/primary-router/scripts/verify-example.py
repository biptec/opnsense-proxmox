#!/usr/bin/env python3
import json
import os
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
expression = '''jsonencode({
  management_ipv4 = var.management_ipv4_address
  management_web  = var.management_web_ipv4_cidr
  wan             = var.wan
  routed          = var.routed_networks
  services        = var.service_networks
  egress          = var.internal_egress_networks
  routed_public   = var.routed_public_subnets
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

assert payload["management_ipv4"] == "10.16.214.2"
assert payload["management_web"] == "10.16.214.6/30"
assert payload["wan"] == {
    "vlan_id": 3801,
    "primary_address": "138.201.128.112",
    "primary_prefix": 26,
    "gateway": "138.201.128.65",
    "public_caddy_address": "138.201.128.87",
    "public_dns_address": "138.201.128.88",
    "dedicated_egress_address": "138.201.128.95",
}

routed = payload["routed"]
assert len(routed) == 1
assert routed["transport_public_routed"]["vlan_id"] == 3802
assert routed["transport_public_routed"]["router_address"] == "5.9.227.113"

services = payload["services"]
assert set(services) == {"dns", "ntp", "caddy", "nat"}
assert services["dns"]["vlan_id"] == 2803 and services["dns"]["subnet"] == "10.16.16.52/30"
assert services["dns"]["service_ipv4_host"] == 1
assert services["ntp"]["vlan_id"] == 2819 and services["ntp"]["subnet"] == "10.16.16.120/30"
assert services["caddy"]["vlan_id"] == 2821 and services["caddy"]["subnet"] == "10.16.16.80/30"
assert services["nat"]["vlan_id"] == 2822 and services["nat"]["subnet"] == "10.16.16.92/30"

assert payload["egress"] == ["10.0.0.0/8"]
assert payload["routed_public"] == ["5.9.227.112/29"]

print("primary-router-example=ok")
