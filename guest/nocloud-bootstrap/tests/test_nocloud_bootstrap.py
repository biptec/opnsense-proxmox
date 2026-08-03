#!/usr/bin/env python3

import os
import stat
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PLUGIN_ROOT / "src/opnsense/scripts/boot/nocloud_bootstrap.py"
PASSWORD_HASH = "$5$testsalt$zs8VOlTYX00XBVLAUSYKi/58OMU9LMjCkjZtiASPsK5"
BCRYPT_PASSWORD_HASH = "$2a$05$lMbqQEJ0KY91rm.rVB.XQu/R6dvSPPzcJx/KAB2B/YnjkDVV6nk5m"
SSH_KEY = "ssh-ed25519 AAAATEST deployment"


class NoCloudBootstrapTest(unittest.TestCase):
    def run_bootstrap(
        self,
        *,
        password=False,
        password_hash=PASSWORD_HASH,
        ssh_key=False,
        network_mode="static",
    ):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root_dir = Path(temporary.name)
        source = root_dir / "cidata"
        source.mkdir()
        config = root_dir / "config.xml"
        marker = root_dir / "bootstrap.done"
        log = root_dir / "bootstrap.log"
        sudoers = root_dir / "sudoers.d"

        config.write_text(
            """<?xml version="1.0"?>
<opnsense>
  <system>
    <hostname>OPNsense</hostname>
    <domain>internal</domain>
    <dnsserver>9.9.9.9</dnsserver>
    <group>
      <name>admins</name><gid>1999</gid><member>0</member><priv>page-all</priv>
    </group>
    <user>
      <name>root</name><uid>0</uid><disabled>0</disabled><password>*</password><descr>Root</descr>
    </user>
    <ssh>
      <group>admins</group><enabled>enabled</enabled>
      <permitrootlogin>1</permitrootlogin><passwordauth>1</passwordauth>
    </ssh>
  </system>
  <interfaces>
    <lan>
      <enable>1</enable><if>vtnet9</if><ipaddr>172.16.0.10</ipaddr>
      <subnet>20</subnet><gateway>IMAGE_GW</gateway>
    </lan>
  </interfaces>
  <OPNsense>
    <Gateways>
      <gateway_item>
        <name>IMAGE_GW</name><interface>lan</interface>
        <gateway>172.16.0.1</gateway><defaultgw>1</defaultgw>
      </gateway_item>
    </Gateways>
  </OPNsense>
</opnsense>
""",
            encoding="utf-8",
        )

        user_data = [
            "#cloud-config",
            "hostname: opnsense-test",
            "fqdn: opnsense-test.example.net",
        ]
        if password or ssh_key:
            user_data.append("user: proxmox")
        if password:
            user_data.append(f"password: '{password_hash}'")
        if ssh_key:
            user_data.extend(["ssh_authorized_keys:", f"  - {SSH_KEY}"])
        (source / "user-data").write_text(
            "\n".join(user_data) + "\n",
            encoding="utf-8",
        )

        if network_mode == "static":
            network_config = """version: 1
config:
  - type: physical
    name: eth0
    mac_address: '02:00:00:00:00:01'
    subnets:
      - type: static
        address: '10.200.0.50'
        netmask: '255.255.255.0'
        gateway: '10.200.0.1'
  - type: nameserver
    address: ['1.1.1.1']
    search: ['example.net']
"""
        elif network_mode == "dhcp":
            network_config = """version: 1
config:
  - type: physical
    name: eth0
    mac_address: '02:00:00:00:00:01'
    subnets:
      - type: dhcp
"""
        elif network_mode == "preserve":
            network_config = """version: 1
config:
"""
        elif network_mode == "preserve_dns":
            network_config = """version: 1
config:
  - type: nameserver
    address: ['1.1.1.1']
    search: ['example.net']
"""
        else:
            raise ValueError(f"unsupported test network mode: {network_mode}")
        (source / "network-config").write_text(network_config, encoding="utf-8")

        env = os.environ.copy()
        env.update(
            {
                "BOOTSTRAP_CONFIG": str(config),
                "BOOTSTRAP_MARKER": str(marker),
                "BOOTSTRAP_LOG": str(log),
                "BOOTSTRAP_SOURCE_DIR": str(source),
                "BOOTSTRAP_SUDOERS_DIR": str(sudoers),
                "BOOTSTRAP_INTERFACE_MAP": '{"02:00:00:00:00:01":"vtnet0"}',
            }
        )
        subprocess.run([sys.executable, str(SCRIPT)], env=env, check=True)
        return ET.parse(config).getroot(), marker, sudoers

    def assert_root_remote_login_disabled(self, system):
        users = {item.findtext("name"): item for item in system.findall("user")}
        self.assertEqual(users["root"].findtext("disabled"), "1")
        self.assertIsNone(users["root"].find("authorizedkeys"))
        ssh = system.find("ssh")
        self.assertIsNone(ssh.find("permitrootlogin"))
        self.assertIsNone(ssh.find("passwordauth"))
        return users, ssh

    def assert_admin_user(self, system, sudoers, expected_password, expect_key):
        users, ssh = self.assert_root_remote_login_disabled(system)
        self.assertIn("proxmox", users)
        user = users["proxmox"]
        self.assertEqual(user.findtext("shell"), "/bin/sh")
        self.assertEqual(user.findtext("password"), expected_password)
        self.assertEqual(user.find("authorizedkeys") is not None, expect_key)
        self.assertEqual(ssh.findtext("enabled") == "enabled", expect_key)

        uid = user.findtext("uid")
        admins = next(
            group for group in system.findall("group")
            if group.findtext("name") == "admins"
        )
        self.assertIn(uid, [member.text for member in admins.findall("member")])

        sudoers_file = sudoers / "proxmox"
        self.assertEqual(
            sudoers_file.read_text(encoding="utf-8"),
            "proxmox ALL=(ALL) NOPASSWD: ALL\n",
        )
        self.assertEqual(stat.S_IMODE(sudoers_file.stat().st_mode), 0o440)

    def test_password_and_key_enable_webui_and_key_only_ssh(self):
        root, marker, sudoers = self.run_bootstrap(password=True, ssh_key=True)
        self.assert_admin_user(root.find("system"), sudoers, PASSWORD_HASH, True)
        self.assertTrue(marker.exists())

    def test_password_only_leaves_ssh_disabled(self):
        root, marker, sudoers = self.run_bootstrap(password=True)
        self.assert_admin_user(root.find("system"), sudoers, PASSWORD_HASH, False)
        self.assertTrue(marker.exists())

    def test_bcrypt_password_is_preserved(self):
        root, marker, sudoers = self.run_bootstrap(
            password=True,
            password_hash=BCRYPT_PASSWORD_HASH,
        )
        self.assert_admin_user(
            root.find("system"), sudoers, BCRYPT_PASSWORD_HASH, False
        )
        self.assertTrue(marker.exists())

    def test_key_only_creates_locked_password(self):
        root, marker, sudoers = self.run_bootstrap(ssh_key=True)
        self.assert_admin_user(root.find("system"), sudoers, "*", True)
        self.assertTrue(marker.exists())

    def test_no_credentials_disables_remote_root_without_creating_user(self):
        root, marker, sudoers = self.run_bootstrap()
        users, ssh = self.assert_root_remote_login_disabled(root.find("system"))
        self.assertNotIn("proxmox", users)
        self.assertIsNone(ssh.find("enabled"))
        self.assertFalse(sudoers.exists())
        self.assertTrue(marker.exists())

    def test_preserve_mode_keeps_image_network(self):
        root, marker, sudoers = self.run_bootstrap(
            password=True,
            network_mode="preserve",
        )
        system = root.find("system")
        lan = root.find("interfaces/lan")
        self.assert_admin_user(system, sudoers, PASSWORD_HASH, False)
        self.assertEqual(system.findtext("hostname"), "opnsense-test")
        self.assertEqual(system.findtext("dnsserver"), "9.9.9.9")
        self.assertEqual(lan.findtext("if"), "vtnet9")
        self.assertEqual(lan.findtext("ipaddr"), "172.16.0.10")
        self.assertEqual(lan.findtext("subnet"), "20")
        self.assertEqual(lan.findtext("gateway"), "IMAGE_GW")
        self.assertTrue(marker.exists())

    def test_preserve_mode_applies_dns_without_changing_network(self):
        root, marker, _ = self.run_bootstrap(network_mode="preserve_dns")
        system = root.find("system")
        lan = root.find("interfaces/lan")
        self.assertEqual(system.findtext("dnsserver"), "1.1.1.1")
        self.assertEqual(lan.findtext("if"), "vtnet9")
        self.assertEqual(lan.findtext("ipaddr"), "172.16.0.10")
        self.assertEqual(lan.findtext("subnet"), "20")
        self.assertEqual(lan.findtext("gateway"), "IMAGE_GW")
        self.assertTrue(marker.exists())

    def test_dhcp_mode_replaces_static_image_network(self):
        root, marker, _ = self.run_bootstrap(network_mode="dhcp")
        lan = root.find("interfaces/lan")
        self.assertEqual(lan.findtext("if"), "vtnet0")
        self.assertEqual(lan.findtext("ipaddr"), "dhcp")
        self.assertIsNone(lan.find("subnet"))
        self.assertIsNone(lan.find("gateway"))
        self.assertEqual(
            [
                item.findtext("interface")
                for item in root.findall("OPNsense/Gateways/gateway_item")
            ],
            [],
        )
        self.assertTrue(marker.exists())

    def test_static_mode_applies_address_gateway_and_dns(self):
        root, marker, _ = self.run_bootstrap(network_mode="static")
        system = root.find("system")
        lan = root.find("interfaces/lan")
        self.assertEqual(lan.findtext("if"), "vtnet0")
        self.assertEqual(lan.findtext("ipaddr"), "10.200.0.50")
        self.assertEqual(lan.findtext("subnet"), "24")
        self.assertEqual(lan.findtext("gateway"), "MGMT_GW")
        self.assertEqual(system.findtext("dnsserver"), "1.1.1.1")
        gateway = root.find("OPNsense/Gateways/gateway_item")
        self.assertEqual(gateway.findtext("name"), "MGMT_GW")
        self.assertEqual(gateway.findtext("gateway"), "10.200.0.1")
        self.assertTrue(marker.exists())


if __name__ == "__main__":
    unittest.main()
