from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("verify_listeners.py")
SPEC = importlib.util.spec_from_file_location("verify_listeners", MODULE_PATH)
assert SPEC and SPEC.loader
verify_listeners = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = verify_listeners
SPEC.loader.exec_module(verify_listeners)


class ListenerVerificationTest(unittest.TestCase):
    def contract(self, listeners):
        handle = tempfile.NamedTemporaryFile("w", delete=False)
        json.dump({"listeners": listeners}, handle)
        handle.close()
        self.addCleanup(Path(handle.name).unlink, missing_ok=True)
        return verify_listeners.load_contract(Path(handle.name))

    def test_exact_ipv4_contract(self):
        expected = self.contract([
            {"name": "bind", "processes": ["named"], "protocols": ["tcp4", "udp4"], "addresses": ["198.51.100.53", "10.53.0.2"], "ports": [53]},
            {"name": "caddy", "processes": ["caddy"], "protocols": ["tcp4"], "addresses": ["198.51.100.80", "10.80.0.2"], "ports": [80, 443]},
        ])
        output = """USER COMMAND PID FD PROTO LOCAL ADDRESS FOREIGN ADDRESS
root named 101 10 tcp4 198.51.100.53:53 *:*
root named 101 11 udp4 198.51.100.53:53 *:*
root named 101 12 tcp4 10.53.0.2:53 *:*
root named 101 13 udp4 10.53.0.2:53 *:*
root caddy 202 10 tcp4 198.51.100.80:80 *:*
root caddy 202 11 tcp4 198.51.100.80:443 *:*
root caddy 202 12 tcp4 10.80.0.2:80 *:*
root caddy 202 13 tcp4 10.80.0.2:443 *:*
"""
        self.assertEqual(verify_listeners.verify(expected, verify_listeners.parse_sockstat(output)), [])

    def test_wildcard_is_unexpected(self):
        expected = self.contract([
            {"name": "bind", "processes": ["named"], "protocols": ["tcp4"], "addresses": ["198.51.100.53"], "ports": [53]}
        ])
        sockets = verify_listeners.parse_sockstat("root named 1 10 tcp4 *:53 *:*\n")
        errors = verify_listeners.verify(expected, sockets)
        self.assertTrue(any("missing listener" in error for error in errors))
        self.assertTrue(any("unexpected listener tcp4 *:53" in error for error in errors))

    def test_wrong_process_is_rejected(self):
        expected = self.contract([
            {"name": "bind", "processes": ["named"], "protocols": ["udp4"], "addresses": ["198.51.100.53"], "ports": [53]}
        ])
        sockets = verify_listeners.parse_sockstat("root dnsmasq 1 10 udp4 198.51.100.53:53 *:*\n")
        errors = verify_listeners.verify(expected, sockets)
        self.assertEqual(len(errors), 1)
        self.assertIn("unexpected process", errors[0])

    def test_ipv6_is_parsed(self):
        sockets = verify_listeners.parse_sockstat("root named 1 10 tcp6 [2001:db8::53]:53 *:*\n")
        self.assertEqual(sockets, [verify_listeners.Socket("named", "tcp6", "2001:db8::53", 53)])

    def test_duplicate_endpoint_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicate endpoint"):
            self.contract([
                {"name": "one", "processes": ["named"], "protocols": ["tcp4"], "addresses": ["198.51.100.53"], "ports": [53]},
                {"name": "two", "processes": ["other"], "protocols": ["tcp4"], "addresses": ["198.51.100.53"], "ports": [53]},
            ])

    def test_contract_rejects_wildcard(self):
        with self.assertRaisesRegex(ValueError, "wildcard"):
            self.contract([
                {"name": "bind", "processes": ["named"], "protocols": ["tcp4"], "addresses": ["*"], "ports": [53]}
            ])

    def test_protocol_address_family_must_match(self):
        with self.assertRaisesRegex(ValueError, "address family"):
            self.contract([
                {"name": "bind", "processes": ["named"], "protocols": ["tcp6"], "addresses": ["198.51.100.53"], "ports": [53]}
            ])


if __name__ == "__main__":
    unittest.main()
