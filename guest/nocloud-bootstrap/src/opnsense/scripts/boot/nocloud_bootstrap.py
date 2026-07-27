#!/usr/local/bin/python3

import base64
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import yaml

CONFIG = Path(os.getenv("BOOTSTRAP_CONFIG", "/conf/config.xml"))
MARKER = Path(os.getenv("BOOTSTRAP_MARKER", "/conf/bootstrap.done"))
LOG_FILE = Path(os.getenv("BOOTSTRAP_LOG", "/var/log/bootstrap.log"))
SOURCE_DIR = os.getenv("BOOTSTRAP_SOURCE_DIR")
SUDOERS_DIR = Path(os.getenv("BOOTSTRAP_SUDOERS_DIR", "/usr/local/etc/sudoers.d"))
CIDATA = Path("/dev/iso9660/cidata")
MOUNT_DIR = Path("/var/run/bootstrap-cidata")


def log(message):
    line = f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {message}"
    print(line)
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def run(command, check=True):
    return subprocess.run(
        command,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def load_yaml(path):
    if not path.exists() or path.stat().st_size == 0:
        return {}
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def interface_map():
    override = os.getenv("BOOTSTRAP_INTERFACE_MAP")
    if override:
        return {key.lower(): value for key, value in json.loads(override).items()}
    result = {}
    for name in run(["/sbin/ifconfig", "-l"]).stdout.split():
        output = run(["/sbin/ifconfig", name], check=False).stdout
        match = re.search(r"\bether\s+([0-9a-f:]{17})", output, re.I)
        if match:
            result[match.group(1).lower()] = name
    return result


def select_network(network):
    nameservers = []
    search_domains = []
    selected = None
    for item in network.get("config", []):
        if not isinstance(item, dict):
            continue
        if item.get("type") == "nameserver":
            nameservers.extend(str(value) for value in item.get("address", []))
            search_domains.extend(str(value) for value in item.get("search", []))
        if item.get("type") != "physical":
            continue
        for subnet in item.get("subnets", []):
            if isinstance(subnet, dict) and subnet.get("type") == "static":
                address = str(subnet.get("address", "")).strip()
                netmask = str(subnet.get("netmask", "")).strip()
                if address and "/" not in address and netmask:
                    prefix = ipaddress.ip_network(f"0.0.0.0/{netmask}").prefixlen
                    address = f"{address}/{prefix}"
                selected = {
                    "mac": str(item.get("mac_address", "")).lower(),
                    "address": address,
                    "gateway": str(subnet.get("gateway", "")),
                }
                break
    return selected, nameservers, search_domains


def ensure(parent, tag):
    node = parent.find(tag)
    if node is None:
        node = ET.SubElement(parent, tag)
    return node


def set_text(parent, tag, value):
    node = ensure(parent, tag)
    node.text = str(value)
    return node


def update_config(user_data, network_data, device):
    selected, nameservers, search_domains = select_network(network_data)
    if not selected:
        raise ValueError("No static physical network found in network-config")
    if not selected["mac"]:
        raise ValueError("Management interface has no mac_address")
    address = ipaddress.ip_interface(selected["address"])
    if address.version != 4:
        raise ValueError("Only IPv4 management addressing is supported")

    tree = ET.parse(CONFIG)
    root = tree.getroot()
    system = ensure(root, "system")
    interfaces = ensure(root, "interfaces")
    lan = ensure(interfaces, "lan")

    fqdn = str(user_data.get("fqdn") or user_data.get("hostname") or "").strip()
    if fqdn:
        hostname, _, domain = fqdn.partition(".")
        set_text(system, "hostname", hostname)
        if domain:
            set_text(system, "domain", domain)
        elif search_domains:
            set_text(system, "domain", search_domains[0])

    set_text(lan, "enable", "1")
    set_text(lan, "if", device)
    set_text(lan, "ipaddr", str(address.ip))
    set_text(lan, "subnet", str(address.network.prefixlen))
    set_text(lan, "ipaddrv6", "")
    set_text(lan, "subnetv6", "")

    if selected["gateway"]:
        set_text(lan, "gateway", "MGMT_GW")
        opnsense = ensure(root, "OPNsense")
        gateways = ensure(opnsense, "Gateways")
        gateway_item = None
        for item in gateways.findall("gateway_item"):
            if item.findtext("name") == "MGMT_GW" or item.findtext("interface") == "lan":
                gateway_item = item
                break
        if gateway_item is None:
            gateway_item = ET.SubElement(gateways, "gateway_item")
        for item in gateways.findall("gateway_item"):
            if item is not gateway_item and item.findtext("defaultgw") == "1":
                set_text(item, "defaultgw", "0")
        set_text(gateway_item, "disabled", "0")
        set_text(gateway_item, "name", "MGMT_GW")
        set_text(gateway_item, "descr", "Management gateway")
        set_text(gateway_item, "interface", "lan")
        set_text(gateway_item, "ipprotocol", "inet")
        set_text(gateway_item, "gateway", selected["gateway"])
        set_text(gateway_item, "defaultgw", "1")
        set_text(gateway_item, "fargw", "0")
        set_text(gateway_item, "monitor_disable", "1")

    set_text(system, "dnsallowoverride", "0")
    for node in list(system.findall("dnsserver")):
        system.remove(node)
    for value in nameservers:
        try:
            ipaddress.ip_address(value)
        except ValueError:
            continue
        node = ET.SubElement(system, "dnsserver")
        node.text = value

    keys = user_data.get("ssh_authorized_keys", user_data.get("ssh-authorized-keys", []))
    if not isinstance(keys, list):
        keys = []
    for user in user_data.get("users", []):
        if not isinstance(user, dict):
            continue
        nested = user.get("ssh_authorized_keys", user.get("ssh-authorized-keys", []))
        if isinstance(nested, list):
            keys.extend(str(value) for value in nested)
    keys = list(dict.fromkeys(str(value).strip() for value in keys if str(value).strip()))

    password_hash = str(user_data.get("password") or "").strip()
    if password_hash in {"", "*", "*0", "!", "!!"}:
        password_hash = ""
    elif not re.match(r"^\$(?:1|5|6|2[abxy]|argon2(?:i|d|id))\$", password_hash):
        raise ValueError("NoCloud password must be a supported crypt hash")

    admin_username = str(user_data.get("user", "")).strip()
    if (keys or password_hash) and not admin_username:
        raise ValueError("NoCloud credentials require a non-empty user field")
    if admin_username:
        if admin_username == "root":
            raise ValueError("NoCloud administration user must not be root")
        if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", admin_username):
            raise ValueError(f"Invalid NoCloud administration username {admin_username!r}")

    root_user = None
    for user in system.findall("user"):
        if user.findtext("name") == "root":
            root_user = user
            break
    if root_user is None:
        raise ValueError("Root user is missing from config.xml")

    # Disable root in OPNsense local authentication. The operating-system root
    # account remains available to the console, but WebUI and API login are denied.
    set_text(root_user, "disabled", "1")

    credentials_present = bool(keys or password_hash)
    if credentials_present:
        admin_user = None
        used_uids = set()
        for user in system.findall("user"):
            try:
                used_uids.add(int(user.findtext("uid", "")))
            except ValueError:
                pass
            if user.findtext("name") == admin_username:
                admin_user = user
        if admin_user is None:
            admin_user = ET.SubElement(system, "user")

        user_uid = admin_user.findtext("uid", "")
        if not user_uid:
            uid = 2000
            while uid in used_uids:
                uid += 1
            user_uid = str(uid)

        set_text(admin_user, "uid", user_uid)
        set_text(admin_user, "name", admin_username)
        set_text(admin_user, "disabled", "0")
        set_text(admin_user, "scope", "user")
        set_text(admin_user, "shell", "/bin/sh")
        set_text(admin_user, "password", password_hash or "*")
        set_text(admin_user, "descr", "NoCloud administration user")

        authorizedkeys = admin_user.find("authorizedkeys")
        if keys:
            encoded = base64.b64encode(("\n".join(keys) + "\n").encode()).decode()
            set_text(admin_user, "authorizedkeys", encoded)
        elif authorizedkeys is not None:
            admin_user.remove(authorizedkeys)

        admins = None
        for group in system.findall("group"):
            if group.findtext("name") == "admins":
                admins = group
                break
        if admins is None:
            raise ValueError("System administrators group is missing from config.xml")
        if user_uid not in [item.text for item in admins.findall("member")]:
            ET.SubElement(admins, "member").text = user_uid

    ssh = ensure(system, "ssh")
    set_text(ssh, "group", "admins")
    for tag in ("permitrootlogin", "passwordauth"):
        node = ssh.find(tag)
        if node is not None:
            ssh.remove(node)
    enabled = ssh.find("enabled")
    if keys:
        set_text(ssh, "enabled", "enabled")
    elif enabled is not None:
        ssh.remove(enabled)

    backup_dir = CONFIG.parent / "backup"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / f"config-bootstrap-{int(time.time())}.xml"
    shutil.copy2(CONFIG, backup)

    fd, tmp_name = tempfile.mkstemp(prefix="config.bootstrap.", dir=str(CONFIG.parent))
    os.close(fd)
    tree.write(tmp_name, encoding="utf-8", xml_declaration=True)
    os.chmod(tmp_name, 0o600)
    os.replace(tmp_name, CONFIG)

    if credentials_present:
        SUDOERS_DIR.mkdir(parents=True, exist_ok=True, mode=0o750)
        sudoers_file = SUDOERS_DIR / admin_username
        sudoers_file.write_text(
            f"{admin_username} ALL=(ALL) NOPASSWD: ALL\n",
            encoding="utf-8",
        )
        os.chmod(sudoers_file, 0o440)

    return address, selected["gateway"], nameservers


def source_directory():
    if SOURCE_DIR:
        return Path(SOURCE_DIR), False
    if not CIDATA.exists():
        raise FileNotFoundError("NoCloud cidata device not found")
    MOUNT_DIR.mkdir(parents=True, exist_ok=True)
    run(["/sbin/mount", "-t", "cd9660", "-o", "ro", str(CIDATA), str(MOUNT_DIR)])
    return MOUNT_DIR, True


def main():
    if MARKER.exists():
        log("bootstrap already completed")
        return 0
    mounted = False
    try:
        source, mounted = source_directory()
        user_data = load_yaml(source / "user-data")
        network_data = load_yaml(source / "network-config")
        selected, _, _ = select_network(network_data)
        if not selected:
            log("no static management network in cidata; nothing to apply")
            return 0
        device = interface_map().get(selected["mac"])
        if not device:
            raise ValueError(f"No interface matches management MAC {selected['mac']}")
        address, gateway, nameservers = update_config(user_data, network_data, device)
        MARKER.write_text("completed\n", encoding="utf-8")
        os.chmod(MARKER, 0o600)
        log(f"configured {device} with {address}; gateway={'set' if gateway else 'none'}; dns={len(nameservers)}")
        return 0
    except Exception as error:
        log(f"bootstrap failed: {error}")
        return 1
    finally:
        if mounted:
            run(["/sbin/umount", str(MOUNT_DIR)], check=False)


if __name__ == "__main__":
    sys.exit(main())
