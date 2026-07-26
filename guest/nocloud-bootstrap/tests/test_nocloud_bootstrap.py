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


class NoCloudBootstrapTest(unittest.TestCase):
    def test_creates_non_root_admin_user(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
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
      <name>root</name><uid>0</uid><password>*</password><descr>Root</descr>
    </user>
    <ssh><group>admins</group></ssh>
  </system>
  <interfaces><lan/></interfaces>
  <OPNsense><Gateways/></OPNsense>
</opnsense>
""",
                encoding="utf-8",
            )
            (source / "user-data").write_text(
                """#cloud-config
hostname: opnsense-test
fqdn: opnsense-test.example.net
user: proxmox
ssh_authorized_keys:
  - ssh-ed25519 AAAATEST deployment
""",
                encoding="utf-8",
            )
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

            tree = ET.parse(config)
            system = tree.getroot().find("system")
            users = {item.findtext("name"): item for item in system.findall("user")}
            self.assertIn("proxmox", users)
            self.assertIsNone(users["root"].find("authorizedkeys"))
            self.assertEqual(users["proxmox"].findtext("shell"), "/bin/sh")
            self.assertEqual(users["proxmox"].findtext("password"), "*")

            ssh = system.find("ssh")
            self.assertEqual(ssh.findtext("enabled"), "enabled")
            self.assertEqual(ssh.findtext("permitrootlogin"), "0")
            self.assertEqual(ssh.findtext("passwordauth"), "0")

            uid = users["proxmox"].findtext("uid")
            admins = next(group for group in system.findall("group") if group.findtext("name") == "admins")
            self.assertIn(uid, [member.text for member in admins.findall("member")])

            sudoers_file = sudoers / "proxmox"
            self.assertEqual(sudoers_file.read_text(encoding="utf-8"), "proxmox ALL=(ALL) NOPASSWD: ALL\n")
            self.assertEqual(stat.S_IMODE(sudoers_file.stat().st_mode), 0o440)
            self.assertTrue(marker.exists())


if __name__ == "__main__":
    unittest.main()
