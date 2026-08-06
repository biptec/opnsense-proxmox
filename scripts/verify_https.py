#!/usr/bin/env python3
"""Verify HTTP(S) endpoints on explicit service listener addresses."""

from __future__ import annotations

import argparse
import datetime as dt
import http.client
import ipaddress
import json
import re
import socket
import ssl
import sys
from pathlib import Path
from typing import Any, Callable

MAX_BODY_DEFAULT = 1024 * 1024
METHODS = {"GET", "HEAD"}
SCHEMES = {"http", "https"}


def _text(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} must be a non-empty string")
    if "\r" in value or "\n" in value:
        raise ValueError(f"{field} must not contain line breaks")
    return value.strip()


def _hostname(value: Any, field: str) -> str:
    hostname = _text(value, field).rstrip(".").lower()
    if len(hostname) > 253:
        raise ValueError(f"{field} is too long")
    labels = hostname.split(".")
    if len(labels) < 2:
        raise ValueError(f"{field} must be a fully qualified hostname")
    for label in labels:
        if not label or len(label) > 63:
            raise ValueError(f"{field} contains an invalid DNS label")
        if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?", label):
            raise ValueError(f"{field} contains an invalid DNS label")
    return hostname


def _string_list(value: Any, field: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise ValueError(f"{field} must be a list")
    return [_text(item, field) for item in value]


def _header_map(value: Any, field: str) -> dict[str, str]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    result: dict[str, str] = {}
    for key, item in value.items():
        name = _text(key, field).lower()
        if not re.fullmatch(r"[!#$%&'*+.^_`|~0-9A-Za-z-]+", name):
            raise ValueError(f"{field} contains an invalid header name")
        result[name] = _text(item, field)
    return result


def _statuses(value: Any, field: str) -> list[int]:
    values = value if isinstance(value, list) else [value]
    if not values or any(not isinstance(item, int) for item in values):
        raise ValueError(f"{field} must contain HTTP status integers")
    if any(item < 100 or item > 599 for item in values):
        raise ValueError(f"{field} contains an invalid HTTP status")
    return list(dict.fromkeys(values))


def load_contract(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or not isinstance(data.get("endpoints"), list):
        raise ValueError("contract must contain an endpoints list")
    endpoints: list[dict[str, Any]] = []
    names: set[str] = set()
    for index, raw in enumerate(data["endpoints"]):
        field = f"endpoints[{index}]"
        if not isinstance(raw, dict):
            raise ValueError(f"{field} must be an object")
        endpoint: dict[str, Any] = {}
        endpoint["name"] = _text(raw.get("name"), f"{field}.name")
        if endpoint["name"] in names:
            raise ValueError(f"duplicate endpoint name: {endpoint['name']}")
        names.add(endpoint["name"])
        endpoint["scheme"] = _text(raw.get("scheme"), f"{field}.scheme").lower()
        if endpoint["scheme"] not in SCHEMES:
            raise ValueError(f"{field}.scheme must be http or https")
        endpoint["host"] = _hostname(raw.get("host"), f"{field}.host")
        address = ipaddress.ip_address(_text(raw.get("address"), f"{field}.address"))
        if address.is_unspecified:
            raise ValueError(f"{field}.address must be an explicit listener address")
        endpoint["address"] = str(address)
        default_port = 443 if endpoint["scheme"] == "https" else 80
        endpoint["port"] = raw.get("port", default_port)
        if not isinstance(endpoint["port"], int) or not 1 <= endpoint["port"] <= 65535:
            raise ValueError(f"{field}.port must be an integer from 1 to 65535")
        endpoint["path"] = _text(raw.get("path", "/"), f"{field}.path")
        if not endpoint["path"].startswith("/"):
            raise ValueError(f"{field}.path must start with /")
        if any(ord(ch) < 0x21 or ord(ch) == 0x7f for ch in endpoint["path"]):
            raise ValueError(f"{field}.path must not contain spaces or control characters")
        endpoint["method"] = _text(raw.get("method", "GET"), f"{field}.method").upper()
        if endpoint["method"] not in METHODS:
            raise ValueError(f"{field}.method must be GET or HEAD")
        endpoint["expected_status"] = _statuses(raw.get("expected_status", 200), f"{field}.expected_status")
        endpoint["expected_headers"] = _header_map(raw.get("expected_headers"), f"{field}.expected_headers")
        endpoint["header_contains"] = _header_map(raw.get("header_contains"), f"{field}.header_contains")
        endpoint["forbidden_headers"] = [item.lower() for item in _string_list(raw.get("forbidden_headers"), f"{field}.forbidden_headers")]
        endpoint["body_contains"] = _string_list(raw.get("body_contains"), f"{field}.body_contains")
        endpoint["body_not_contains"] = _string_list(raw.get("body_not_contains"), f"{field}.body_not_contains")
        endpoint["redirect_location"] = raw.get("redirect_location")
        if endpoint["redirect_location"] is not None:
            endpoint["redirect_location"] = _text(endpoint["redirect_location"], f"{field}.redirect_location")
        endpoint["timeout_seconds"] = raw.get("timeout_seconds", 10)
        if not isinstance(endpoint["timeout_seconds"], (int, float)) or endpoint["timeout_seconds"] <= 0:
            raise ValueError(f"{field}.timeout_seconds must be positive")
        endpoint["max_body_bytes"] = raw.get("max_body_bytes", MAX_BODY_DEFAULT)
        if not isinstance(endpoint["max_body_bytes"], int) or endpoint["max_body_bytes"] < 0:
            raise ValueError(f"{field}.max_body_bytes must be a non-negative integer")
        endpoint["ca_file"] = raw.get("ca_file")
        if endpoint["ca_file"] is not None:
            ca_file = Path(_text(endpoint["ca_file"], f"{field}.ca_file"))
            endpoint["ca_file"] = str(ca_file if ca_file.is_absolute() else path.parent / ca_file)
        endpoint["min_valid_days"] = raw.get("min_valid_days", 14)
        if not isinstance(endpoint["min_valid_days"], int) or endpoint["min_valid_days"] < 0:
            raise ValueError(f"{field}.min_valid_days must be a non-negative integer")
        endpoint["issuer_contains"] = _string_list(raw.get("issuer_contains"), f"{field}.issuer_contains")
        raw_sans = raw.get("expected_sans", [endpoint["host"]])
        endpoint["expected_sans"] = [
            _hostname(item, f"{field}.expected_sans")
            for item in _string_list(raw_sans, f"{field}.expected_sans")
        ]
        if endpoint["scheme"] == "https" and not endpoint["expected_sans"]:
            raise ValueError(f"{field}.expected_sans must not be empty for HTTPS")
        endpoints.append(endpoint)
    return {"endpoints": endpoints}


def _request_bytes(endpoint: dict[str, Any]) -> bytes:
    lines = [
        f"{endpoint['method']} {endpoint['path']} HTTP/1.1",
        f"Host: {endpoint['host']}",
        "User-Agent: opnsense-deployment-verifier/1",
        "Accept: */*",
        "Connection: close",
        "",
        "",
    ]
    return "\r\n".join(lines).encode("ascii")


def _issuer_text(certificate: dict[str, Any]) -> str:
    parts: list[str] = []
    for group in certificate.get("issuer", ()):
        for key, value in group:
            parts.append(f"{key}={value}")
    return ", ".join(parts)


def _sans(certificate: dict[str, Any]) -> list[str]:
    return sorted(
        value.lower().rstrip(".")
        for kind, value in certificate.get("subjectAltName", ())
        if kind == "DNS"
    )


def fetch_endpoint(endpoint: dict[str, Any]) -> dict[str, Any]:
    timeout = float(endpoint["timeout_seconds"])
    raw_socket = socket.create_connection((endpoint["address"], endpoint["port"]), timeout=timeout)
    connection: socket.socket = raw_socket
    certificate: dict[str, Any] | None = None
    try:
        if endpoint["scheme"] == "https":
            context = ssl.create_default_context(cafile=endpoint["ca_file"])
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            connection = context.wrap_socket(raw_socket, server_hostname=endpoint["host"])
            certificate = connection.getpeercert()
        connection.settimeout(timeout)
        connection.sendall(_request_bytes(endpoint))
        response = http.client.HTTPResponse(connection)
        response.begin()
        headers: dict[str, str] = {}
        for key, value in response.getheaders():
            lowered = key.lower()
            headers[lowered] = f"{headers[lowered]}, {value}" if lowered in headers else value
        maximum = endpoint["max_body_bytes"]
        body = response.read(maximum + 1)
        if len(body) > maximum:
            raise ValueError(f"response body exceeds max_body_bytes={maximum}")
        return {
            "status": response.status,
            "headers": headers,
            "body": body.decode("utf-8", errors="replace"),
            "certificate": certificate,
        }
    finally:
        connection.close()


def verify_endpoint(endpoint: dict[str, Any], result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if result["status"] not in endpoint["expected_status"]:
        errors.append(f"status {result['status']} not in {endpoint['expected_status']}")
    headers = result["headers"]
    for name, expected in endpoint["expected_headers"].items():
        actual = headers.get(name)
        if actual != expected:
            errors.append(f"header {name!r} is {actual!r}, expected {expected!r}")
    for name, expected in endpoint["header_contains"].items():
        actual = headers.get(name, "")
        if expected.lower() not in actual.lower():
            errors.append(f"header {name!r} does not contain {expected!r}")
    for name in endpoint["forbidden_headers"]:
        if name in headers:
            errors.append(f"forbidden header {name!r} is present")
    if endpoint["redirect_location"] is not None:
        actual = headers.get("location")
        if actual != endpoint["redirect_location"]:
            errors.append(f"redirect location is {actual!r}, expected {endpoint['redirect_location']!r}")
    body = result["body"]
    for marker in endpoint["body_contains"]:
        if marker not in body:
            errors.append(f"response body does not contain {marker!r}")
    for marker in endpoint["body_not_contains"]:
        if marker.lower() in body.lower():
            errors.append(f"response body contains forbidden marker {marker!r}")
    return errors


def verify_certificate(endpoint: dict[str, Any], result: dict[str, Any]) -> list[str]:
    if endpoint["scheme"] != "https":
        return []
    certificate = result.get("certificate")
    if not certificate:
        return ["TLS certificate details are unavailable"]
    errors: list[str] = []
    actual_sans = set(_sans(certificate))
    missing_sans = sorted(set(endpoint["expected_sans"]) - actual_sans)
    if missing_sans:
        errors.append(f"certificate is missing SANs: {missing_sans}")
    issuer = _issuer_text(certificate)
    for marker in endpoint["issuer_contains"]:
        if marker.lower() not in issuer.lower():
            errors.append(f"certificate issuer does not contain {marker!r}: {issuer!r}")
    not_after = certificate.get("notAfter")
    if not not_after:
        errors.append("certificate notAfter is unavailable")
    else:
        expires = dt.datetime.fromtimestamp(ssl.cert_time_to_seconds(not_after), tz=dt.timezone.utc)
        remaining = expires - dt.datetime.now(dt.timezone.utc)
        minimum = dt.timedelta(days=endpoint["min_valid_days"])
        if remaining < minimum:
            errors.append(
                f"certificate expires too soon: {expires.isoformat()} "
                f"(< {endpoint['min_valid_days']} days)"
            )
    return errors


def verify(
    contract: dict[str, Any],
    fetcher: Callable[[dict[str, Any]], dict[str, Any]] = fetch_endpoint,
) -> list[str]:
    errors: list[str] = []
    for endpoint in contract["endpoints"]:
        try:
            result = fetcher(endpoint)
        except Exception as exc:
            errors.append(f"{endpoint['name']}: request failed: {exc}")
            continue
        endpoint_errors = verify_endpoint(endpoint, result)
        endpoint_errors.extend(verify_certificate(endpoint, result))
        errors.extend(f"{endpoint['name']}: {message}" for message in endpoint_errors)
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("contract", type=Path)
    args = parser.parse_args(argv)
    try:
        contract = load_contract(args.contract)
        errors = verify(contract)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    for endpoint in contract["endpoints"]:
        print(f"PASS: {endpoint['name']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
