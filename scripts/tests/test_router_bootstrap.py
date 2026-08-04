import importlib.util
import pathlib
import sys
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).parents[1] / "router-bootstrap.py"
SPEC = importlib.util.spec_from_file_location("router_bootstrap", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


BASE_CONFIG = {
    "api_username": "sysops",
    "management_interface": "lan",
    "management_ip": "10.200.0.100",
    "management_fqdn": "router1.biptec.net",
    "webui_port": 10443,
    "ca_name": "biptec.net",
    "ca_country": "NL",
    "ca_key_type": "4096",
    "ca_digest": "sha256",
    "ca_lifetime_days": 3650,
}


class FakeApi:
    def __init__(self, ca_rows=None, cert_rows=None):
        self.ca_rows = list(ca_rows or [])
        self.cert_rows = list(cert_rows or [])
        self.requests = []

    def search(self, path):
        if path.endswith("/ca/search"):
            return list(self.ca_rows)
        if path.endswith("/cert/search"):
            return list(self.cert_rows)
        raise AssertionError(path)

    def request(self, path, method="GET", payload=None):
        self.requests.append((path, method, payload))
        if path.endswith("/ca/add"):
            self.ca_rows.append(
                {
                    "uuid": "ca-uuid",
                    "refid": "ca-ref",
                    "descr": "biptec.net",
                    "commonname": "biptec.net",
                    "key_type": "4096",
                    "digest": "sha256",
                    "country": "NL",
                    "crt_payload": "-----BEGIN CERTIFICATE-----\nCA\n-----END CERTIFICATE-----\n",
                }
            )
            return {"result": "saved", "uuid": "ca-uuid"}
        if path.endswith("/cert/add"):
            self.cert_rows.append(
                {
                    "uuid": "cert-uuid",
                    "refid": "cert-ref",
                    "commonname": "router1.biptec.net",
                    "caref": "ca-ref",
                    "cert_type": "server_cert",
                    "altnames_dns": "router1.biptec.net",
                    "altnames_ip": "10.200.0.100",
                }
            )
            return {"result": "saved", "uuid": "cert-uuid"}
        raise AssertionError(path)


class RouterBootstrapTests(unittest.TestCase):
    def test_credentials_require_both_values(self):
        self.assertIsNone(MODULE.Credentials.from_mapping({"key": "only"}))
        credentials = MODULE.Credentials.from_mapping({"key": "key", "secret": "secret"})
        self.assertEqual(credentials.key, "key")
        self.assertEqual(credentials.secret, "secret")

    def test_ca_payload_uses_global_policy(self):
        payload = MODULE.ca_payload(BASE_CONFIG)["ca"]
        self.assertEqual(payload["descr"], "biptec.net")
        self.assertEqual(payload["commonname"], "biptec.net")
        self.assertEqual(payload["country"], "NL")
        self.assertEqual(payload["key_type"], "4096")
        self.assertEqual(payload["lifetime"], "3650")

    def test_ensure_ca_creates_once(self):
        api = FakeApi()
        first = MODULE.ensure_ca(api, BASE_CONFIG)
        second = MODULE.ensure_ca(api, BASE_CONFIG)
        self.assertEqual(first["uuid"], "ca-uuid")
        self.assertEqual(second["uuid"], "ca-uuid")
        self.assertEqual(len([item for item in api.requests if item[0].endswith("/ca/add")]), 1)

    def test_existing_ca_mismatch_is_rejected(self):
        api = FakeApi(
            ca_rows=[
                {
                    "uuid": "ca-uuid",
                    "refid": "ca-ref",
                    "descr": "biptec.net",
                    "commonname": "biptec.net",
                    "key_type": "2048",
                    "digest": "sha256",
                    "country": "NL",
                    "crt_payload": "-----BEGIN CERTIFICATE-----\nCA\n",
                }
            ]
        )
        with self.assertRaises(MODULE.BootstrapError):
            MODULE.ensure_ca(api, BASE_CONFIG)

    def test_certificate_contains_management_dns_and_ip_sans(self):
        api = FakeApi()
        ca = MODULE.ensure_ca(api, BASE_CONFIG)
        certificate = MODULE.ensure_certificate(api, BASE_CONFIG, ca)
        self.assertEqual(certificate["refid"], "cert-ref")
        payload = next(item[2]["cert"] for item in api.requests if item[0].endswith("/cert/add"))
        self.assertEqual(payload["altnames_dns"], "router1.biptec.net")
        self.assertEqual(payload["altnames_ip"], "10.200.0.100")
        self.assertEqual(payload["lifetime"], "3650")

    def test_local_api_candidates_cover_configured_and_default_ports(self):
        self.assertEqual(
            MODULE.local_api_urls(BASE_CONFIG),
            ["https://127.0.0.1:10443", "https://127.0.0.1"],
        )

    @mock.patch.object(MODULE, "LocalApi")
    def test_local_api_falls_back_to_default_port_on_first_boot(self, api_class):
        configured = mock.Mock()
        configured.search.side_effect = MODULE.BootstrapError("not listening")
        default = mock.Mock()
        default.search.return_value = []
        api_class.side_effect = [configured, default]
        credentials = MODULE.Credentials("key", "secret")
        selected = MODULE.connect_local_api(BASE_CONFIG, credentials)
        self.assertIs(selected, default)
        self.assertEqual(
            [call.args[1] for call in api_class.call_args_list],
            ["https://127.0.0.1:10443", "https://127.0.0.1"],
        )

    def test_webui_template_reserves_public_ports_for_caddy(self):
        self.assertIn("'port' => (string)$data['port']", MODULE.WEBGUI_PHP)
        self.assertIn("'interfaces' => (string)$data['interface']", MODULE.WEBGUI_PHP)
        self.assertIn("disablehttpredirect", MODULE.WEBGUI_PHP)
        self.assertIn("ssl-certref", MODULE.WEBGUI_PHP)


if __name__ == "__main__":
    unittest.main()
