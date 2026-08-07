#!/usr/bin/env python3
import json
import os
import subprocess
import tempfile
from pathlib import Path

import yaml

root = Path(__file__).resolve().parents[1]
expr = '''jsonencode({
  network = local.network_data
  bind_options = local.bind_options
  bind_local = nonsensitive(local.bind_local)
  chrony = local.chrony_config
  nftables = local.nftables_config
  user_data = nonsensitive(local.user_data)
  trunks = local.trunk_vlans
})
'''
cmd = [
    "tofu", "console",
    "-var-file=terraform.tfvars.example",
    "-var=proxmox_endpoint=https://127.0.0.1:8006",
    "-var=proxmox_api_token=test@pam!test=test",
    "-var=transfer_tsig_secret=dGVzdC10cmFuc2Zlci1rZXk=",
]
result = subprocess.run(cmd, cwd=root, input=expr, text=True, capture_output=True, check=True)
payload = json.loads(json.loads(result.stdout.strip()))

network = yaml.safe_load(payload["network"])
assert network["version"] == 2
assert set(network["ethernets"]) == {"mgmt0", "trunk0"}
assert network["ethernets"]["mgmt0"]["addresses"] == [
    "10.16.222.2/30",
    "2a07:e580:a10:de00::2/64",
]
assert network["ethernets"]["trunk0"].get("addresses") is None
assert network["vlans"]["alcor"]["id"] == 2804
assert network["vlans"]["kochab"]["id"] == 2820
assert network["vlans"]["public"]["id"] == 3802
assert {p["from"]: p["table"] for p in network["vlans"]["alcor"]["routing-policy"]}[
    "10.16.18.53/32"
] == 2804
assert {p["from"]: p["table"] for p in network["vlans"]["kochab"]["routing-policy"]}[
    "10.16.18.122/32"
] == 2820
assert {p["from"]: p["table"] for p in network["vlans"]["public"]["routing-policy"]}[
    "5.9.227.114/32"
] == 3802
assert network["vlans"]["alcor"]["nameservers"]["addresses"] == ["10.16.16.53"]

bind = payload["bind_options"] + "\n" + payload["bind_local"]
assert 'listen-on port 53 { 10.16.18.53; 5.9.227.114; };' in bind
assert 'listen-on-v6 port 53 { 2a07:e580:a10:1234::2; };' in bind
assert 'view "internal"' in bind and 'recursion yes;' in bind
assert 'transfer-source 10.16.18.53;' in bind
assert 'primaries { 10.16.16.53 key "secondary-transfer.biptec.net"; };' in bind
assert 'allow-notify { 10.16.18.54; };' in bind
assert 'view "public"' in bind and 'match-destinations { 5.9.227.114; };' in bind
assert 'transfer-source 5.9.227.114;' in bind
assert 'primaries { 138.201.128.88 key "secondary-transfer.biptec.net"; };' in bind
assert 'allow-notify { 5.9.227.113; };' in bind

with tempfile.TemporaryDirectory() as tmp:
    cache = Path(tmp) / "cache"
    (cache / "internal").mkdir(parents=True)
    (cache / "public").mkdir(parents=True)
    conf = Path(tmp) / "named.conf"
    conf.write_text(bind.replace("/var/cache/bind", str(cache)))
    subprocess.run(["named-checkconf", str(conf)], check=True)

chrony = payload["chrony"]
assert "bindaddress 10.16.18.122" in chrony
assert "bindaddress 2a07:e580:a10:1278::2" in chrony
assert "allow 10.0.0.0/8" in chrony
assert "allow 2a07:e580:a10::/48" in chrony

nft = payload["nftables"]
assert 'iifname "public" udp dport 53 accept' in nft
assert 'iifname "public" tcp dport 53 accept' in nft
assert 'iifname "kochab" ip saddr @internal_v4 udp dport 123 accept' in nft
assert 'iifname "public" udp dport 123' not in nft

user_data = payload["user_data"]
assert user_data.startswith("#cloud-config\n")
cloud = yaml.safe_load(user_data.split("\n", 1)[1])
assert cloud["ssh_pwauth"] is False and cloud["disable_root"] is True
assert {"bind9", "chrony", "nftables", "qemu-guest-agent"}.issubset(set(cloud["packages"]))
assert any(f["path"] == "/etc/bind/named.conf.local" and f["permissions"] == "0600" for f in cloud["write_files"])
assert payload["trunks"] == "2804;2820;3802"

print("secondary-dns-render=ok")
