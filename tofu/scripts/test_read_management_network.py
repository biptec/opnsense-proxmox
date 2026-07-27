#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("read-management-network.py")
SPEC = importlib.util.spec_from_file_location("management_network", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ManagementNetworkTest(unittest.TestCase):
    def test_matches_management_mac_and_preserves_prefix(self):
        interfaces = [
            {
                "name": "lo0",
                "hardware-address": "00:00:00:00:00:00",
                "ip-addresses": [
                    {
                        "ip-address-type": "ipv4",
                        "ip-address": "127.0.0.1",
                        "prefix": 8,
                    }
                ],
            },
            {
                "name": "vtnet0",
                "hardware-address": "02:00:00:00:00:01",
                "ip-addresses": [
                    {
                        "ip-address-type": "ipv4",
                        "ip-address": "10.200.16.7",
                        "prefix": 20,
                    }
                ],
            },
        ]
        result = MODULE.find_management_network(
            interfaces,
            MODULE.normalize_mac("02-00-00-00-00-01"),
        )
        self.assertEqual(result, ("10.200.16.7", "255.255.240.0"))

    def test_reads_token_from_standard_tfvars_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            token_file = Path(temporary) / "token.auto.tfvars"
            token_file.write_text(
                'proxmox_api_token = "user@pve!name=secret"\n',
                encoding="utf-8",
            )
            self.assertEqual(
                MODULE.token_from_file(token_file),
                "user@pve!name=secret",
            )


if __name__ == "__main__":
    unittest.main()
