from __future__ import annotations

import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("verify_dns.py")
SPEC = importlib.util.spec_from_file_location("verify_dns", MODULE_PATH)
assert SPEC and SPEC.loader
verify_dns = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = verify_dns
SPEC.loader.exec_module(verify_dns)


def response(*, status="NOERROR", flags="qr aa", answer=(), authority=(), returncode=0, stderr=""):
    sections = [
        f";; ->>HEADER<<- opcode: QUERY, status: {status}, id: 1",
        f";; flags: {flags}; QUERY: 1, ANSWER: {len(answer)}, AUTHORITY: {len(authority)}, ADDITIONAL: 0",
        "",
        ";; ANSWER SECTION:",
        *answer,
        "",
        ";; AUTHORITY SECTION:",
        *authority,
        "",
    ]
    return verify_dns.DigResult(returncode, "\n".join(sections), stderr)


class FakeDig:
    def __init__(self, zone="example.net.", primary="192.0.2.53", secondary="198.51.100.54"):
        self.zone = zone
        self.primary = primary
        self.secondary = secondary
        self.calls = []
        self.primary_serial = 2026080601
        self.secondary_serial = 2026080601
        self.fail_authenticated_axfr = False

    def run(self, server, name, record_type, *options, key_file=None):
        self.calls.append((server, name, record_type, options, key_file))
        record_type = record_type.upper()
        if record_type == "A" and name == "www.example.net.":
            return response(answer=("www.example.net. 300 IN A 203.0.113.20",))
        if record_type == "DNSKEY":
            return response(answer=(
                "example.net. 300 IN DNSKEY 257 3 13 AAAATESTKEY",
                "example.net. 300 IN RRSIG DNSKEY 13 2 300 20260901000000 20260801000000 12345 example.net. SIGNATURE",
            ))
        if record_type == "SOA":
            serial = self.primary_serial if server == self.primary else self.secondary_serial
            return response(answer=(
                f"example.net. 300 IN SOA ns1.example.net. hostmaster.example.net. {serial} 3600 600 1209600 300",
            ))
        if record_type == "AXFR":
            if key_file is not None and server == self.primary and not self.fail_authenticated_axfr:
                output = "\n".join((
                    "example.net. 300 IN SOA ns1.example.net. hostmaster.example.net. 2026080601 3600 600 1209600 300",
                    "www.example.net. 300 IN A 203.0.113.20",
                    "example.net. 300 IN SOA ns1.example.net. hostmaster.example.net. 2026080601 3600 600 1209600 300",
                ))
                return verify_dns.DigResult(0, output, "")
            return verify_dns.DigResult(9, "; Transfer failed.\n", "")
        if name == "_dns-verification-nonexistent.example.net.":
            return response(
                status="NXDOMAIN",
                answer=(),
                authority=(
                    "example.net. 300 IN SOA ns1.example.net. hostmaster.example.net. 2026080601 3600 600 1209600 300",
                    "example.net. 300 IN RRSIG SOA 13 2 300 20260901000000 20260801000000 12345 example.net. SIGNATURE",
                ),
            )
        if name == "example.org.":
            return response(status="REFUSED", flags="qr rd", answer=())
        raise AssertionError(f"unexpected dig call: {server} {name} {record_type} {options}")


class DNSVerificationTest(unittest.TestCase):
    def write_contract(self, **updates):
        data = {
            "zone": "example.net",
            "primary": "192.0.2.53",
            "secondary": "198.51.100.54",
            "authoritative_probe": {
                "name": "www.example.net",
                "type": "A",
                "expected_values": ["203.0.113.20"],
            },
            "recursion_probe": {"name": "example.org", "type": "A"},
            "secondary_sync_timeout_seconds": 1,
            "transfer_tsig": {
                "name": "secondary-transfer.example.net",
                "algorithm": "hmac-sha256",
            },
        }
        data.update(updates)
        handle = tempfile.NamedTemporaryFile("w", delete=False)
        json.dump(data, handle)
        handle.close()
        path = Path(handle.name)
        self.addCleanup(path.unlink, missing_ok=True)
        return path


    def test_dig_command_includes_server_transport_and_key_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args_path = root / "args.txt"
            fake_dig = root / "dig"
            fake_dig.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$@\" > \"$DNS_FAKE_ARGS\"\n"
                "printf '%s\\n' ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1'\n"
                "printf '%s\\n' ';; flags: qr aa; QUERY: 1, ANSWER: 0, AUTHORITY: 0, ADDITIONAL: 0'\n"
            )
            fake_dig.chmod(fake_dig.stat().st_mode | stat.S_IXUSR)
            key_file = root / "key.conf"
            key_file.write_text("key test {};")
            old_value = os.environ.get("DNS_FAKE_ARGS")
            os.environ["DNS_FAKE_ARGS"] = str(args_path)
            try:
                result = verify_dns.Dig(str(fake_dig)).run(
                    "192.0.2.53", "example.net.", "SOA", "+norecurse", "+tcp", key_file=key_file
                )
            finally:
                if old_value is None:
                    os.environ.pop("DNS_FAKE_ARGS", None)
                else:
                    os.environ["DNS_FAKE_ARGS"] = old_value
            self.assertEqual(result.returncode, 0)
            arguments = args_path.read_text().splitlines()
            self.assertEqual(arguments[:3], ["@192.0.2.53", "example.net.", "SOA"])
            self.assertIn("+tcp", arguments)
            self.assertIn("+norecurse", arguments)
            self.assertEqual(arguments[arguments.index("-k") + 1], str(key_file))

    def test_parses_header_flags_and_sections(self):
        result = response(
            answer=("www.example.net. 300 IN A 203.0.113.20",),
            authority=("example.net. 300 IN NS ns1.example.net.",),
        )
        self.assertEqual(result.status, "NOERROR")
        self.assertEqual(result.flags, {"qr", "aa"})
        self.assertEqual(result.answer_lines, ["www.example.net. 300 IN A 203.0.113.20"])
        self.assertEqual(result.authority_lines, ["example.net. 300 IN NS ns1.example.net."])

    def test_parses_soa_serial(self):
        serial = verify_dns.parse_soa_serial([
            "example.net. 300 IN SOA ns1.example.net. hostmaster.example.net. 2026080601 3600 600 1209600 300"
        ], "example.net")
        self.assertEqual(serial, 2026080601)

    def test_full_verification_succeeds(self):
        contract = verify_dns.load_contract(self.write_contract())
        fake = FakeDig()
        errors = verify_dns.verify(contract, fake, "c2Vjb25kYXJ5LXRyYW5zZmVyLXNlY3JldA==")
        self.assertEqual(errors, [])
        transports = {
            options for _, name, record_type, options, _ in fake.calls
            if name == "www.example.net." and record_type == "A"
        }
        self.assertIn(("+norecurse", "+notcp"), transports)
        self.assertIn(("+norecurse", "+tcp"), transports)
        key_paths = [key_file for _, _, record_type, _, key_file in fake.calls if record_type == "AXFR" and key_file is not None]
        self.assertEqual(len(key_paths), 1)
        self.assertFalse(key_paths[0].exists())

    def test_recursion_available_is_rejected(self):
        class RecursiveFake(FakeDig):
            def run(self, server, name, record_type, *options, key_file=None):
                if name == "example.org.":
                    return response(status="NOERROR", flags="qr rd ra", answer=("example.org. 300 IN A 203.0.113.9",))
                return super().run(server, name, record_type, *options, key_file=key_file)

        errors = verify_dns.verify(verify_dns.load_contract(self.write_contract()), RecursiveFake(), "c2VjcmV0")
        self.assertTrue(any("RA flag" in error for error in errors))
        self.assertTrue(any("recursive answer" in error for error in errors))

    def test_missing_dnssec_signature_is_rejected(self):
        class UnsignedFake(FakeDig):
            def run(self, server, name, record_type, *options, key_file=None):
                if record_type.upper() == "DNSKEY":
                    return response(answer=("example.net. 300 IN DNSKEY 257 3 13 AAAATESTKEY",))
                return super().run(server, name, record_type, *options, key_file=key_file)

        errors = verify_dns.verify(verify_dns.load_contract(self.write_contract()), UnsignedFake(), "c2VjcmV0")
        self.assertTrue(any("RRSIG record is missing" in error for error in errors))


    def test_unsigned_nxdomain_is_rejected(self):
        class UnsignedNegativeFake(FakeDig):
            def run(self, server, name, record_type, *options, key_file=None):
                if name == "_dns-verification-nonexistent.example.net.":
                    return response(
                        status="NXDOMAIN",
                        authority=(
                            "example.net. 300 IN SOA ns1.example.net. hostmaster.example.net. 2026080601 3600 600 1209600 300",
                        ),
                    )
                return super().run(server, name, record_type, *options, key_file=key_file)

        errors = verify_dns.verify(verify_dns.load_contract(self.write_contract()), UnsignedNegativeFake(), "c2VjcmV0")
        self.assertTrue(any("NXDOMAIN: RRSIG authority record is missing" in error for error in errors))

    def test_external_delegation_succeeds(self):
        class DelegationFake(FakeDig):
            def run(self, server, name, record_type, *options, key_file=None):
                if server == "9.9.9.9" and name == "example.net." and record_type.upper() == "NS":
                    return response(answer=(
                        "example.net. 300 IN NS ns1.example.net.",
                        "example.net. 300 IN NS ns2.example.net.",
                    ))
                if server == "9.9.9.9" and name == "example.net." and record_type.upper() == "DS":
                    return response(answer=(
                        "example.net. 300 IN DS 12345 13 2 ABCDEF",
                    ))
                return super().run(server, name, record_type, *options, key_file=key_file)

        contract = verify_dns.load_contract(self.write_contract(delegation={
            "resolver": "9.9.9.9",
            "nameservers": ["ns1.example.net", "ns2.example.net"],
            "require_ds": True,
            "expected_ds": ["12345 13 2 ABCDEF"],
        }))
        self.assertEqual(verify_dns.verify(contract, DelegationFake(), "c2VjcmV0"), [])

    def test_missing_delegation_ds_is_rejected(self):
        class MissingDSFake(FakeDig):
            def run(self, server, name, record_type, *options, key_file=None):
                if server == "9.9.9.9" and record_type.upper() == "NS":
                    return response(answer=("example.net. 300 IN NS ns1.example.net.",))
                if server == "9.9.9.9" and record_type.upper() == "DS":
                    return response(answer=())
                return super().run(server, name, record_type, *options, key_file=key_file)

        contract = verify_dns.load_contract(self.write_contract(delegation={
            "resolver": "9.9.9.9",
            "nameservers": ["ns1.example.net"],
            "require_ds": True,
        }))
        errors = verify_dns.verify(contract, MissingDSFake(), "c2VjcmV0")
        self.assertTrue(any("DS record is missing" in error for error in errors))

    def test_unexpected_authoritative_value_is_rejected(self):
        contract = verify_dns.load_contract(self.write_contract(authoritative_probe={
            "name": "www.example.net", "type": "A", "expected_values": ["203.0.113.99"]
        }))
        errors = verify_dns.verify(contract, FakeDig(), "c2VjcmV0")
        self.assertTrue(any("expected ['203.0.113.99']" in error for error in errors))

    def test_unauthenticated_axfr_success_is_rejected(self):
        class OpenTransferFake(FakeDig):
            def run(self, server, name, record_type, *options, key_file=None):
                if record_type.upper() == "AXFR" and key_file is None:
                    output = "\n".join((
                        "example.net. 300 IN SOA ns1.example.net. hostmaster.example.net. 1 3600 600 1209600 300",
                        "example.net. 300 IN SOA ns1.example.net. hostmaster.example.net. 1 3600 600 1209600 300",
                    ))
                    return verify_dns.DigResult(0, output, "")
                return super().run(server, name, record_type, *options, key_file=key_file)

        errors = verify_dns.verify(verify_dns.load_contract(self.write_contract()), OpenTransferFake(), "c2VjcmV0")
        self.assertTrue(any("unauthenticated AXFR unexpectedly succeeded" in error for error in errors))

    def test_authenticated_axfr_failure_is_rejected(self):
        fake = FakeDig()
        fake.fail_authenticated_axfr = True
        errors = verify_dns.verify(verify_dns.load_contract(self.write_contract()), fake, "c2VjcmV0")
        self.assertTrue(any("authenticated AXFR failed" in error for error in errors))

    def test_serial_mismatch_times_out(self):
        fake = FakeDig()
        fake.secondary_serial = 2026080501
        errors = verify_dns.verify(verify_dns.load_contract(self.write_contract()), fake, "c2VjcmV0")
        self.assertTrue(any("SOA serials did not match" in error for error in errors))

    def test_contract_rejects_same_server_address(self):
        with self.assertRaisesRegex(ValueError, "must be different"):
            verify_dns.load_contract(self.write_contract(secondary="192.0.2.53"))

    def test_contract_rejects_probe_outside_zone(self):
        with self.assertRaisesRegex(ValueError, "must be inside zone"):
            verify_dns.load_contract(self.write_contract(authoritative_probe={
                "name": "www.other.net", "type": "A", "expected_values": []
            }))

    def test_key_file_permissions_and_content(self):
        path = verify_dns.write_key_file("hmac-sha256", "secondary-transfer.example.net", "c2VjcmV0")
        self.addCleanup(path.unlink, missing_ok=True)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        content = path.read_text()
        self.assertIn('key "secondary-transfer.example.net."', content)
        self.assertIn("algorithm hmac-sha256;", content)
        self.assertIn('secret "c2VjcmV0";', content)


    def test_invalid_tsig_secret_encoding_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "valid Base64"):
            verify_dns.write_key_file("hmac-sha256", "key.example.net", "not-base64")

    def test_invalid_dns_name_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "invalid DNS name"):
            verify_dns.normalize_name('bad"name.example.net')

    def test_invalid_tsig_algorithm_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "unsupported TSIG"):
            verify_dns.write_key_file("hmac-md5", "key.example.net", "secret")


if __name__ == "__main__":
    unittest.main()
