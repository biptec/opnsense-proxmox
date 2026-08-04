import importlib.util
import json
import os
import pathlib
import stat
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).parents[1] / "deploy.py"
SPEC = importlib.util.spec_from_file_location("router_deploy", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class DeployTests(unittest.TestCase):
    def test_ssh_options_use_dedicated_known_hosts(self):
        options = MODULE.ssh_options(
            pathlib.Path("/tmp/id_ed25519"),
            pathlib.Path("/tmp/known_hosts"),
        )
        self.assertIn("StrictHostKeyChecking=accept-new", options)
        self.assertIn("UserKnownHostsFile=/tmp/known_hosts", options)
        self.assertIn("IdentitiesOnly=yes", options)

    def test_atomic_write_sets_requested_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "secret.json"
            MODULE.atomic_write(path, "secret\n", 0o600)
            mode = stat.S_IMODE(path.stat().st_mode)
            self.assertEqual(mode, 0o600)
            self.assertEqual(path.read_text(), "secret\n")

    def test_persist_result_keeps_private_key_material_out_of_ca_file(self):
        result = {
            "version": 1,
            "uri": "https://10.200.0.100:10443",
            "key": "api-key",
            "secret": "api-secret",
            "ca_certificate": "-----BEGIN CERTIFICATE-----\nCA\n-----END CERTIFICATE-----\n",
            "ca_uuid": "ca-uuid",
            "ca_ref_id": "ca-ref",
        }
        with tempfile.TemporaryDirectory() as directory:
            credentials = pathlib.Path(directory) / "credentials.json"
            certificate = pathlib.Path(directory) / "ca.pem"
            environment = MODULE.persist_bootstrap_result(result, credentials, certificate)
            stored = json.loads(credentials.read_text())
            self.assertNotIn("ca_certificate", stored)
            self.assertEqual(stored["secret"], "api-secret")
            self.assertNotIn("api-secret", certificate.read_text())
            self.assertEqual(environment["OPNSENSE_ALLOW_INSECURE"], "false")
            self.assertEqual(environment["SSL_CERT_FILE"], str(certificate.resolve()))

    def test_load_credentials_rejects_incomplete_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "credentials.json"
            path.write_text('{"key":"only"}')
            with self.assertRaises(MODULE.DeployError):
                MODULE.load_credentials(path)

    @mock.patch.object(MODULE.subprocess, "run")
    @mock.patch.object(MODULE, "run")
    def test_global_settings_are_imported_only_when_absent(self, run_mock, state_mock):
        state_mock.return_value = mock.Mock(returncode=1, stdout="", stderr="No state file was found")
        run_mock.return_value = mock.Mock(returncode=0, stdout="", stderr="")
        MODULE.apply_global_config(pathlib.Path("/tmp/router"), {}, True)
        commands = [call.args[0] for call in run_mock.call_args_list]
        imports = [command for command in commands if "import" in command]
        self.assertEqual(len(imports), 1)
        self.assertIn("opnsense_caddy_settings.main", imports[0])
        self.assertIn("caddy_settings", imports[0])


if __name__ == "__main__":
    unittest.main()
