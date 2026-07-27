#!/usr/bin/env python3

import ipaddress
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def normalize_mac(value):
    return re.sub(r"[^0-9a-f]", "", str(value).lower())


def token_from_file(path):
    token_file = Path(path)
    if not token_file.is_file():
        return None
    text = token_file.read_text(encoding="utf-8")
    match = re.search(
        r'^\s*proxmox_api_token\s*=\s*("(?:\\.|[^"\\])*")\s*$',
        text,
        re.MULTILINE,
    )
    if not match:
        return None
    try:
        return json.loads(match.group(1))
    except json.JSONDecodeError as error:
        fail(f"cannot parse proxmox_api_token from {token_file}: {error}")


def load_token(query):
    for name in (
        "PROXMOX_VE_API_TOKEN",
        "PM_VE_API_TOKEN",
        "TF_VAR_proxmox_api_token",
    ):
        value = os.getenv(name)
        if value:
            return value
    value = token_from_file(query.get("token_file", ""))
    if value:
        return value
    fail(
        "Proxmox API token is unavailable; set PROXMOX_VE_API_TOKEN, "
        "TF_VAR_proxmox_api_token, or create tofu/token.auto.tfvars"
    )


def api_url(query):
    endpoint = query["endpoint"].rstrip("/")
    node = urllib.parse.quote(query["node_name"], safe="")
    vm_id = urllib.parse.quote(query["vm_id"], safe="")
    return (
        f"{endpoint}/api2/json/nodes/{node}/qemu/{vm_id}/"
        "agent/network-get-interfaces"
    )


def request_interfaces(query, token):
    request = urllib.request.Request(
        api_url(query),
        headers={"Authorization": f"PVEAPIToken={token}"},
        method="GET",
    )
    context = ssl.create_default_context()
    if query.get("insecure", "false").lower() == "true":
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen(request, context=context, timeout=30) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        message = f"Proxmox Guest Agent API returned HTTP {error.code}"
        if error.code in {401, 403, 404}:
            raise PermissionError(message) from error
        raise RuntimeError(message) from error
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"cannot read Proxmox Guest Agent network data: {error}"
        ) from error
    data = payload.get("data") or {}
    result = data.get("result") or []
    if not isinstance(result, list):
        raise RuntimeError("unexpected Proxmox Guest Agent network response")
    return result


def find_management_network(interfaces, target_mac):
    for interface in interfaces:
        if normalize_mac(interface.get("hardware-address", "")) != target_mac:
            continue
        for item in interface.get("ip-addresses") or []:
            if item.get("ip-address-type") != "ipv4":
                continue
            try:
                address = ipaddress.ip_address(item.get("ip-address", ""))
                prefix = int(item.get("prefix"))
                network = ipaddress.ip_interface(f"{address}/{prefix}")
            except (ValueError, TypeError):
                continue
            if address.is_loopback or address.is_link_local or address.is_unspecified:
                continue
            return str(address), str(network.netmask)
    return "", ""


def main():
    try:
        query = json.load(sys.stdin)
    except json.JSONDecodeError as error:
        fail(f"invalid external data query: {error}")

    token = load_token(query)
    target_mac = normalize_mac(query.get("management_mac", ""))
    if not target_mac:
        fail("management MAC address is unavailable")

    management_ip = ""
    management_netmask = ""
    last_error = None
    attempts = 10
    for attempt in range(attempts):
        try:
            interfaces = request_interfaces(query, token)
        except PermissionError as error:
            fail(str(error))
        except RuntimeError as error:
            last_error = error
        else:
            last_error = None
            management_ip, management_netmask = find_management_network(
                interfaces,
                target_mac,
            )
            if management_ip:
                break
        if attempt < attempts - 1:
            time.sleep(2)
    if last_error is not None:
        fail(str(last_error))

    json.dump(
        {
            "management_ip": management_ip,
            "management_netmask": management_netmask,
        },
        sys.stdout,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
