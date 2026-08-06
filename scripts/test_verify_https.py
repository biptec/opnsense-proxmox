from __future__ import annotations

import datetime as dt
import importlib.util
import json
import os
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("verify_https.py")
SPEC = importlib.util.spec_from_file_location("verify_https", MODULE_PATH)
assert SPEC and SPEC.loader
verify_https = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = verify_https
SPEC.loader.exec_module(verify_https)


def certificate(*, san: str = "service.example.test", days: int = 90) -> dict:
    expires = dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=days)
    return {
        "subjectAltName": (("DNS", san),),
        "issuer": ((('organizationName', 'Example CA'),),),
        "notAfter": expires.strftime("%b %d %H:%M:%S %Y GMT"),
    }


def response(**updates):
    result = {
        "status": 200,
        "headers": {"server": "Caddy", "x-content-type-options": "nosniff"},
        "body": "backend ok",
        "certificate": certificate(),
    }
    result.update(updates)
    return result


class HTTPSVerificationTest(unittest.TestCase):
    def write_contract(self, endpoint_updates=None) -> Path:
        endpoint = {
            "name": "public service",
            "scheme": "https",
            "host": "service.example.test",
            "address": "192.0.2.80",
            "expected_status": 200,
            "expected_headers": {"server": "Caddy"},
            "header_contains": {"x-content-type-options": "nosniff"},
            "forbidden_headers": ["x-opnsense-version"],
            "body_contains": ["backend ok"],
            "body_not_contains": ["OPNsense WebGUI"],
            "issuer_contains": ["Example CA"],
            "expected_sans": ["service.example.test"],
            "min_valid_days": 30,
        }
        if endpoint_updates:
            endpoint.update(endpoint_updates)
        handle = tempfile.NamedTemporaryFile("w", delete=False)
        json.dump({"endpoints": [endpoint]}, handle)
        handle.close()
        path = Path(handle.name)
        self.addCleanup(path.unlink, missing_ok=True)
        return path

    def test_loads_exact_listener_contract(self):
        endpoint = verify_https.load_contract(self.write_contract())["endpoints"][0]
        self.assertEqual(endpoint["address"], "192.0.2.80")
        self.assertEqual(endpoint["port"], 443)
        self.assertEqual(endpoint["host"], "service.example.test")
        self.assertEqual(endpoint["expected_status"], [200])

    def test_rejects_duplicate_endpoint_names(self):
        path = self.write_contract()
        data = json.loads(path.read_text())
        data["endpoints"].append(dict(data["endpoints"][0]))
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "duplicate endpoint name"):
            verify_https.load_contract(path)

    def test_rejects_invalid_contract_values(self):
        for updates in (
            {"scheme": "ftp"},
            {"host": "single-label"},
            {"address": "not-an-ip"},
            {"address": "0.0.0.0"},
            {"port": 70000},
            {"path": "no-leading-slash"},
            {"path": "/bad path"},
            {"host": "sérvice.example.test"},
            {"method": "POST"},
            {"expected_status": 99},
            {"expected_sans": "service.example.test"},
            {"expected_sans": []},
            {"expected_headers": {"bad header": "value"}},
            {"max_body_bytes": -1},
        ):
            with self.subTest(updates=updates):
                with self.assertRaises(ValueError):
                    verify_https.load_contract(self.write_contract(updates))

    def test_request_uses_configured_host_and_path(self):
        endpoint = verify_https.load_contract(
            self.write_contract({"path": "/health?full=1", "method": "HEAD"})
        )["endpoints"][0]
        request = verify_https._request_bytes(endpoint).decode()
        self.assertIn("HEAD /health?full=1 HTTP/1.1\r\n", request)
        self.assertIn("Host: service.example.test\r\n", request)

    def test_full_verification_succeeds(self):
        contract = verify_https.load_contract(self.write_contract())
        self.assertEqual(verify_https.verify(contract, lambda _: response()), [])

    def test_status_header_and_body_failures_are_reported(self):
        contract = verify_https.load_contract(self.write_contract())
        result = response(
            status=503,
            headers={"x-opnsense-version": "26.7"},
            body="OPNsense WebGUI",
        )
        errors = verify_https.verify(contract, lambda _: result)
        self.assertTrue(any("status 503" in item for item in errors))
        self.assertTrue(any("header 'server'" in item for item in errors))
        self.assertTrue(any("forbidden header" in item for item in errors))
        self.assertTrue(any("forbidden marker" in item for item in errors))

    def test_redirect_location_is_exact(self):
        contract = verify_https.load_contract(
            self.write_contract({
                "scheme": "http",
                "port": 80,
                "expected_status": 308,
                "redirect_location": "https://service.example.test/",
                "expected_headers": {},
                "header_contains": {},
            })
        )
        errors = verify_https.verify(
            contract,
            lambda _: response(status=308, headers={"location": "https://wrong.example.test/"}),
        )
        self.assertTrue(any("redirect location" in item for item in errors))

    def test_certificate_san_issuer_and_expiry_are_checked(self):
        contract = verify_https.load_contract(self.write_contract())
        bad = certificate(san="other.example.test", days=1)
        bad["issuer"] = ((('organizationName', 'Wrong CA'),),)
        errors = verify_https.verify(contract, lambda _: response(certificate=bad))
        self.assertTrue(any("missing SANs" in item for item in errors))
        self.assertTrue(any("issuer does not contain" in item for item in errors))
        self.assertTrue(any("expires too soon" in item for item in errors))

    def test_fetch_failure_is_scoped_to_endpoint(self):
        contract = verify_https.load_contract(self.write_contract())

        def fail(_):
            raise TimeoutError("connection timed out")

        errors = verify_https.verify(contract, fail)
        self.assertEqual(len(errors), 1)
        self.assertIn("public service: request failed", errors[0])

    def test_response_body_limit_is_enforced(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"12345")

            def log_message(self, *_args):
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            endpoint = verify_https.load_contract(self.write_contract({
                "scheme": "http", "address": "127.0.0.1", "port": server.server_port,
                "max_body_bytes": 4, "expected_headers": {}, "header_contains": {},
                "body_contains": [], "issuer_contains": [],
            }))["endpoints"][0]
            with self.assertRaisesRegex(ValueError, "response body exceeds"):
                verify_https.fetch_endpoint(endpoint)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_relative_ca_file_uses_contract_directory(self):
        path = self.write_contract({"ca_file": "ca.pem"})
        endpoint = verify_https.load_contract(path)["endpoints"][0]
        self.assertEqual(endpoint["ca_file"], str(path.parent / "ca.pem"))

    def test_real_tls_connection_uses_explicit_ip_sni_and_host(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cert_path = root / "cert.pem"
            key_path = root / "key.pem"
            subprocess.run(
                [
                    "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-days", "30", "-subj", "/CN=service.example.test",
                    "-addext", "subjectAltName=DNS:service.example.test",
                    "-keyout", str(key_path), "-out", str(cert_path),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            observed = {}

            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    observed["host"] = self.headers.get("Host")
                    self.send_response(200)
                    self.send_header("X-Proxy", "Caddy")
                    self.end_headers()
                    self.wfile.write(b"backend ok")

                def log_message(self, *_args):
                    return
            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(certfile=cert_path, keyfile=key_path)

            def capture_sni(_socket, server_name, _context):
                observed["sni"] = server_name

            context.set_servername_callback(capture_sni)
            server.socket = context.wrap_socket(server.socket, server_side=True)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.addCleanup(server.server_close)
            self.addCleanup(server.shutdown)
            contract = verify_https.load_contract(
                self.write_contract({
                    "address": "127.0.0.1",
                    "port": server.server_port,
                    "ca_file": str(cert_path),
                    "expected_headers": {"x-proxy": "Caddy"},
                    "header_contains": {},
                    "issuer_contains": [],
                    "min_valid_days": 1,
                })
            )
            errors = verify_https.verify(contract)
            self.assertEqual(errors, [])
            self.assertEqual(observed["sni"], "service.example.test")
            self.assertEqual(observed["host"], "service.example.test")
            server.shutdown()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
