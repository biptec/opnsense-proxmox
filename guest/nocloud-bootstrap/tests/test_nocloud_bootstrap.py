#!/usr/bin/env python3

import os
import stat
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PLUGIN_ROOT / "src/opnsense/scripts/boot/nocloud_bootstrap.py"
PASSWORD_HASH = "$5$testsalt$zs8VOlTYX00XBVLAUSYKi/58OMU9LMjCkjZtiASPsK5"
SSH_KEY = "ssh-ed25519 AAAATEST deployment"


class NoCloudBootstrapTest(unittest.TestCase):
    def run_bootstrap(self, *, password=False, ssh_key=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        source = root / "cidata"
        source.mkdir()
        config = root / "config.xml"
        marker = root / "bootstrap.done"
        log = root / "bootstrap.log"
        sudoers = root / "sudoers.d"

        config.write_text(
            """<?xml version="1.0"?>
<opnsense>
  <system>
    <hostname>OPNsense</hostname>
    <domain>internal</domain>
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
  <interfaces><lan/></interfaces>
  <OPNsense><Gateways/></OPNsense>
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
            user_data.append(f"password: '{PASSWORD_HASH}'")
        if ssh_key:
            user_data.extend(["ssh_authorized_keys:", f"  - {SSH_KEY}"])
        (source / "user-data").write_text("\n".join(user_data) + "\n", encoding="utf-8")

        (source / "network-config").write_text(
            """version: 1
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
""",
            encoding="utf-8",
        )

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
        subprocess.run([str(SCRIPT)], env=env, check=True)
        return ET.parse(config).getroot().find("system"), marker, sudoers

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
        admins = next(group for group in system.findall("group") if group.findtext("name") == "admins")
        self.assertIn(uid, [member.text for member in admins.findall("member")])

        sudoers_file = sudoers / "proxmox"
        self.assertEqual(sudoers_file.read_text(encoding="utf-8"), "proxmox ALL=(ALL) NOPASSWD: ALL\n")
        self.assertEqual(stat.S_IMODE(sudoers_file.stat().st_mode), 0o440)

    def test_password_and_key_enable_webui_and_key_only_ssh(self):
        system, marker, sudoers = self.run_bootstrap(password=True, ssh_key=True)
        self.assert_admin_user(system, sudoers, PASSWORD_HASH, True)
        self.assertTrue(marker.exists())

    def test_password_only_leaves_ssh_disabled(self):
        system, marker, sudoers = self.run_bootstrap(password=True)
        self.assert_admin_user(system, sudoers, PASSWORD_HASH, False)
        self.assertTrue(marker.exists())

    def test_key_only_creates_locked_password(self):
        system, marker, sudoers = self.run_bootstrap(ssh_key=True)
        self.assert_admin_user(system, sudoers, "*", True)
        self.assertTrue(marker.exists())

    def test_no_credentials_disables_remote_root_without_creating_user(self):
        system, marker, sudoers = self.run_bootstrap()
        users, ssh = self.assert_root_remote_login_disabled(system)
        self.assertNotIn("proxmox", users)
        self.assertIsNone(ssh.find("enabled"))
        self.assertFalse(sudoers.exists())
        self.assertTrue(marker.exists())


if __name__ == "__main__":
    unittest.main()
