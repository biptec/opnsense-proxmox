#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parents[3]
root = repo / "tofu"
values = repo / "platform/primary-router/vm-bootstrap.tfvars.example"
cmd = [
    "tofu", "console", f"-var-file={values}",
    "-var=proxmox_endpoint=https://127.0.0.1:8006",
    "-var=proxmox_api_token=test@pam!test=test",
]
result = subprocess.run(
    cmd,
    cwd=root,
    input="jsonencode({bridge=var.bridge, vm_started=var.vm_started, vm_on_boot=var.vm_on_boot, additional_nics=var.additional_nics})\n",
    text=True,
    capture_output=True,
    check=True,
)
payload = json.loads(json.loads(result.stdout.strip()))
assert payload["bridge"] == "vmbr2"
assert payload["vm_started"] is True
assert payload["vm_on_boot"] is True
nics = payload["additional_nics"]
assert len(nics) == 1
assert nics[0]["bridge"] == "vmbr1"
assert nics[0]["trunks"] is None
assert nics[0]["mac_address"].lower() == "90:1b:0e:95:a1:0b"
print("primary-router-bootstrap-example=ok")
