#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parents[3]
root = repo / "tofu"
base = repo / "platform/primary-router/vm-bootstrap.tfvars.example"
staging = repo / "platform/primary-router/vm-bootstrap-staging.tfvars.example"


def additional_nics(*var_files):
    cmd = ["tofu", "console"]
    for path in var_files:
        cmd.append(f"-var-file={path}")
    cmd.extend([
        "-var=proxmox_endpoint=https://127.0.0.1:8006",
        "-var=proxmox_api_token=test@pam!test=test",
    ])
    result = subprocess.run(
        cmd,
        cwd=root,
        input="jsonencode(var.additional_nics)\n",
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(json.loads(result.stdout.strip()))


staged = additional_nics(base, staging)
assert len(staged) == 1
assert staged[0]["bridge"] == "vmbr1"
assert staged[0]["trunks"] == "508;2804;2820;3802"
assert "3801" not in staged[0]["trunks"].split(";")

final = additional_nics(base)
assert len(final) == 1
assert final[0]["bridge"] == "vmbr1"
assert final[0]["trunks"] is None

print("primary-router-bootstrap-staging=ok")
