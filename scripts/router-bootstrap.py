#!/usr/local/bin/python3
"""Idempotently prepare a freshly deployed OPNsense router.

The script runs as root inside OPNsense over an authenticated SSH session.
Configuration is read from stdin and one result object is written to stdout.
"""

from __future__ import annotations

import base64
import json
import os
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

DEFAULT_API_URL = "https://127.0.0.1"


class BootstrapError(RuntimeError):
    """Raised when the router cannot be prepared safely."""


@dataclass(frozen=True)
class Credentials:
    key: str
    secret: str

    @classmethod
    def from_mapping(cls, value: Any) -> "Credentials | None":
        if not isinstance(value, dict):
            return None
        key = str(value.get("key", "")).strip()
        secret = str(value.get("secret", "")).strip()
        if not key or not secret:
            return None
        return cls(key=key, secret=secret)


class LocalApi:
    def __init__(self, credentials: Credentials, base_url: str = DEFAULT_API_URL):
        self.credentials = credentials
        self.base_url = base_url.rstrip("/")
        self.context = ssl._create_unverified_context()

    def request(self, path: str, method: str = "GET", payload: Any = None) -> dict[str, Any]:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(self.base_url + path, data=body, method=method)
        token = base64.b64encode(
            f"{self.credentials.key}:{self.credentials.secret}".encode("utf-8")
        ).decode("ascii")
        request.add_header("Authorization", f"Basic {token}")
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, context=self.context, timeout=20) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            message = exc.read().decode("utf-8", "replace")
            raise BootstrapError(f"OPNsense API {method} {path} failed: HTTP {exc.code}: {message}") from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            raise BootstrapError(f"OPNsense API {method} {path} failed: {exc}") from exc

    def search(self, path: str) -> list[dict[str, Any]]:
        result = self.request(path, method="POST", payload={})
        rows = result.get("rows", [])
        if not isinstance(rows, list):
            raise BootstrapError(f"Unexpected search response from {path}")
        return rows


def require_text(config: dict[str, Any], key: str) -> str:
    value = str(config.get(key, "")).strip()
    if not value:
        raise BootstrapError(f"Missing required setting: {key}")
    return value


def create_credentials(username: str) -> Credentials:
    command = [
        "/usr/local/sbin/opnsense-apikey",
        "--user",
        username,
        "--json",
        "create",
    ]
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    try:
        credentials = Credentials.from_mapping(json.loads(result.stdout))
    except json.JSONDecodeError as exc:
        raise BootstrapError("opnsense-apikey returned invalid JSON") from exc
    if credentials is None:
        raise BootstrapError("opnsense-apikey did not return a key and secret")
    return credentials


def local_api_urls(config: dict[str, Any]) -> list[str]:
    configured_port = int(config.get("webui_port", 10443))
    urls = [f"https://127.0.0.1:{configured_port}", DEFAULT_API_URL]
    return list(dict.fromkeys(urls))


def connect_local_api(config: dict[str, Any], credentials: Credentials) -> LocalApi:
    errors: list[str] = []
    for base_url in local_api_urls(config):
        api = LocalApi(credentials, base_url)
        try:
            api.search("/api/trust/ca/search")
            return api
        except BootstrapError as exc:
            errors.append(f"{base_url}: {exc}")
    raise BootstrapError("Unable to connect to the local OPNsense API: " + "; ".join(errors))


def resolve_credentials(config: dict[str, Any]) -> tuple[Credentials, LocalApi]:
    existing = Credentials.from_mapping(config.get("credentials"))
    if existing is not None:
        try:
            return existing, connect_local_api(config, existing)
        except BootstrapError:
            pass
    credentials = create_credentials(require_text(config, "api_username"))
    return credentials, connect_local_api(config, credentials)


def matching_rows(rows: list[dict[str, Any]], **criteria: str) -> list[dict[str, Any]]:
    return [
        row
        for row in rows
        if all(str(row.get(key, "")) == expected for key, expected in criteria.items())
    ]


def exactly_one(rows: list[dict[str, Any]], label: str) -> dict[str, Any]:
    if len(rows) != 1:
        raise BootstrapError(f"Expected exactly one {label}, found {len(rows)}")
    return rows[0]


def ca_payload(config: dict[str, Any]) -> dict[str, Any]:
    name = require_text(config, "ca_name")
    return {
        "ca": {
            "descr": name,
            "action": "internal",
            "caref": "",
            "key_type": str(config.get("ca_key_type", "4096")),
            "lifetime": str(config.get("ca_lifetime_days", 3650)),
            "digest": str(config.get("ca_digest", "sha256")),
            "country": str(config.get("ca_country", "NL")),
            "state": str(config.get("ca_state", "")),
            "city": str(config.get("ca_city", "")),
            "organization": str(config.get("ca_organization", "")),
            "organizationalunit": str(config.get("ca_organizational_unit", "")),
            "email": str(config.get("ca_email", "")),
            "commonname": name,
            "ocsp_uri": "",
            "crt_payload": "",
            "prv_payload": "",
        }
    }


def verify_ca(row: dict[str, Any], config: dict[str, Any]) -> None:
    expected = {
        "descr": require_text(config, "ca_name"),
        "commonname": require_text(config, "ca_name"),
        "key_type": str(config.get("ca_key_type", "4096")),
        "digest": str(config.get("ca_digest", "sha256")),
        "country": str(config.get("ca_country", "NL")),
    }
    mismatches = [
        f"{key}={row.get(key)!r}, expected {value!r}"
        for key, value in expected.items()
        if str(row.get(key, "")) != value
    ]
    if mismatches:
        raise BootstrapError("Existing CA does not match bootstrap policy: " + "; ".join(mismatches))


def ensure_ca(api: LocalApi, config: dict[str, Any]) -> dict[str, Any]:
    name = require_text(config, "ca_name")
    rows = matching_rows(api.search("/api/trust/ca/search"), descr=name, commonname=name)
    if not rows:
        response = api.request("/api/trust/ca/add", method="POST", payload=ca_payload(config))
        if response.get("result") != "saved" or not response.get("uuid"):
            raise BootstrapError(f"Unable to create CA: {response}")
        rows = matching_rows(api.search("/api/trust/ca/search"), descr=name, commonname=name)
    ca = exactly_one(rows, f"CA {name!r}")
    verify_ca(ca, config)
    if not str(ca.get("crt_payload", "")).startswith("-----BEGIN CERTIFICATE-----"):
        raise BootstrapError("CA public certificate is missing")
    if not ca.get("refid") or not ca.get("uuid"):
        raise BootstrapError("CA identifiers are missing")
    return ca


def certificate_payload(config: dict[str, Any], ca_ref_id: str) -> dict[str, Any]:
    fqdn = require_text(config, "management_fqdn")
    address = require_text(config, "management_ip")
    return {
        "cert": {
            "descr": f"Web GUI TLS certificate ({require_text(config, 'ca_name')})",
            "caref": ca_ref_id,
            "action": "internal",
            "key_type": str(config.get("certificate_key_type", "2048")),
            "digest": str(config.get("certificate_digest", "sha256")),
            "cert_type": "server_cert",
            "lifetime": str(config.get("certificate_lifetime_days", 3650)),
            "private_key_location": "firewall",
            "country": str(config.get("ca_country", "NL")),
            "state": str(config.get("ca_state", "")),
            "city": str(config.get("ca_city", "")),
            "organization": str(config.get("ca_organization", "")),
            "organizationalunit": str(config.get("ca_organizational_unit", "")),
            "email": str(config.get("ca_email", "")),
            "commonname": fqdn,
            "ocsp_uri": "",
            "altnames_dns": fqdn,
            "altnames_ip": address,
            "altnames_uri": "",
            "altnames_email": "",
            "crt_payload": "",
            "csr_payload": "",
            "prv_payload": "",
            "rfc3280_purpose": "",
        }
    }


def ensure_certificate(api: LocalApi, config: dict[str, Any], ca: dict[str, Any]) -> dict[str, Any]:
    fqdn = require_text(config, "management_fqdn")
    rows = matching_rows(
        api.search("/api/trust/cert/search"),
        commonname=fqdn,
        caref=str(ca["refid"]),
        cert_type="server_cert",
    )
    if not rows:
        response = api.request(
            "/api/trust/cert/add",
            method="POST",
            payload=certificate_payload(config, str(ca["refid"])),
        )
        if response.get("result") != "saved" or not response.get("uuid"):
            raise BootstrapError(f"Unable to create WebUI certificate: {response}")
        rows = matching_rows(
            api.search("/api/trust/cert/search"),
            commonname=fqdn,
            caref=str(ca["refid"]),
            cert_type="server_cert",
        )
    certificate = exactly_one(rows, f"WebUI certificate for {fqdn!r}")
    dns_names = str(certificate.get("altnames_dns", "")).splitlines()
    ip_names = str(certificate.get("altnames_ip", "")).splitlines()
    if fqdn not in dns_names or require_text(config, "management_ip") not in ip_names:
        raise BootstrapError("Existing WebUI certificate does not contain the required SANs")
    if not certificate.get("refid") or not certificate.get("uuid"):
        raise BootstrapError("WebUI certificate identifiers are missing")
    return certificate


WEBGUI_PHP = r'''<?php
require_once 'script/load_phalcon.php';
use OPNsense\Core\Config;
$data = json_decode(stream_get_contents(STDIN), true);
if (!is_array($data)) {
    fwrite(STDERR, "invalid input\n");
    exit(1);
}
$config = Config::getInstance();
$config->lock();
$changed = false;
try {
    $webgui = $config->object()->system->webgui;
    $values = [
        'protocol' => 'https',
        'port' => (string)$data['port'],
        'interfaces' => (string)$data['interface'],
        'ssl-certref' => (string)$data['certificate_ref_id'],
        'althostnames' => (string)$data['fqdn'],
    ];
    foreach ($values as $key => $value) {
        if ((string)$webgui->{$key} !== $value) {
            $webgui->{$key} = $value;
            $changed = true;
        }
    }
    if (!isset($webgui->disablehttpredirect)) {
        $webgui->disablehttpredirect = '1';
        $changed = true;
    }
    if ($changed) {
        $config->save([
            'username' => 'router-bootstrap',
            'description' => 'Configure management WebUI',
        ]);
    }
} finally {
    $config->unlock();
}
echo json_encode(['changed' => $changed]) . "\n";
'''


def configure_webgui(config: dict[str, Any], certificate_ref_id: str) -> bool:
    payload = {
        "port": int(config.get("webui_port", 10443)),
        "interface": require_text(config, "management_interface"),
        "certificate_ref_id": certificate_ref_id,
        "fqdn": require_text(config, "management_fqdn"),
    }
    path = ""
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".php", delete=False) as handle:
            handle.write(WEBGUI_PHP)
            path = handle.name
        os.chmod(path, 0o600)
        result = subprocess.run(
            ["/usr/local/bin/php", path],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=True,
        )
        response = json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        stderr = getattr(exc, "stderr", "")
        raise BootstrapError(f"Unable to configure WebUI: {stderr}") from exc
    finally:
        if path:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
    changed = bool(response.get("changed"))
    if changed:
        subprocess.run(
            ["/usr/local/sbin/configctl", "webgui", "restart", "3"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    return changed


def wait_for_webui(
    config: dict[str, Any], credentials: Credentials, ca_certificate: str
) -> str:
    address = require_text(config, "management_ip")
    port = int(config.get("webui_port", 10443))
    uri = f"https://{address}:{port}"
    context = ssl.create_default_context()
    context.load_verify_locations(cadata=ca_certificate)
    token = base64.b64encode(
        f"{credentials.key}:{credentials.secret}".encode("utf-8")
    ).decode("ascii")
    deadline = time.monotonic() + int(config.get("webui_timeout_seconds", 60))
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        request = urllib.request.Request(
            uri + "/api/trust/ca/search",
            data=b"{}",
            method="POST",
            headers={
                "Authorization": f"Basic {token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, context=context, timeout=5) as response:
                json.load(response)
            return uri
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            last_error = exc
            time.sleep(2)
    raise BootstrapError(f"WebUI did not become ready at {uri}: {last_error}")


def main() -> int:
    try:
        config = json.load(sys.stdin)
        if not isinstance(config, dict):
            raise BootstrapError("Bootstrap input must be a JSON object")
        credentials, api = resolve_credentials(config)
        ca = ensure_ca(api, config)
        certificate = ensure_certificate(api, config, ca)
        configure_webgui(config, str(certificate["refid"]))
        ca_certificate = str(ca["crt_payload"])
        uri = wait_for_webui(config, credentials, ca_certificate)
        result = {
            "version": 1,
            "uri": uri,
            "key": credentials.key,
            "secret": credentials.secret,
            "ca_certificate": ca_certificate,
            "ca_uuid": str(ca["uuid"]),
            "ca_ref_id": str(ca["refid"]),
            "webui_certificate_uuid": str(certificate["uuid"]),
            "webui_certificate_ref_id": str(certificate["refid"]),
        }
        json.dump(result, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0
    except (BootstrapError, OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"router bootstrap failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
