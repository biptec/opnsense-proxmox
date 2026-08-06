#!/usr/bin/env python3
"""Verify primary and secondary authoritative DNS behavior with dig."""

from __future__ import annotations

import argparse
import base64
import binascii
import ipaddress
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

HEADER_RE = re.compile(r"status:\s*([A-Z]+)")
FLAGS_RE = re.compile(r";; flags:\s*([^;]+);")


@dataclass(frozen=True)
class DigResult:
    returncode: int
    stdout: str
    stderr: str

    @property
    def status(self) -> str:
        match = HEADER_RE.search(self.stdout)
        return match.group(1) if match else ""

    @property
    def flags(self) -> set[str]:
        match = FLAGS_RE.search(self.stdout)
        return set(match.group(1).split()) if match else set()

    @property
    def answer_lines(self) -> list[str]:
        return record_lines(self.stdout, "ANSWER")

    @property
    def authority_lines(self) -> list[str]:
        return record_lines(self.stdout, "AUTHORITY")


def record_lines(output: str, section: str) -> list[str]:
    marker = f";; {section} SECTION:"
    lines: list[str] = []
    active = False
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if line.startswith(";; ") and line.endswith(" SECTION:"):
            active = line == marker
            continue
        if active and line and not line.startswith(";"):
            lines.append(line)
    return lines


def normalize_name(value: str, *, allow_underscore: bool = True) -> str:
    name = value.strip().lower().rstrip(".")
    if not name or len(name) > 253:
        raise ValueError("DNS name must contain 1 to 253 characters")
    labels = name.split(".")
    if allow_underscore:
        label_pattern = re.compile(r"^[a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])?$")
    else:
        label_pattern = re.compile(r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$")
    if any(len(label) > 63 or not label_pattern.fullmatch(label) for label in labels):
        raise ValueError(f"invalid DNS name: {value!r}")
    return name + "."


def parse_soa_serial(lines: Iterable[str], zone: str) -> int:
    expected = normalize_name(zone)
    for line in lines:
        fields = line.split()
        if len(fields) >= 7 and normalize_name(fields[0]) == expected and fields[3].upper() == "SOA":
            try:
                return int(fields[6])
            except ValueError as exc:
                raise ValueError(f"invalid SOA serial in line: {line}") from exc
    raise ValueError(f"SOA record for {expected} not found")


def record_types(lines: Iterable[str]) -> set[str]:
    types: set[str] = set()
    for line in lines:
        fields = line.split()
        if len(fields) >= 4:
            types.add(fields[3].upper())
    return types


def record_values(lines: Iterable[str], name: str, record_type: str) -> list[str]:
    expected_name = normalize_name(name)
    expected_type = record_type.upper()
    values: list[str] = []
    for line in lines:
        fields = line.split()
        if len(fields) >= 5 and normalize_name(fields[0]) == expected_name and fields[3].upper() == expected_type:
            values.append(" ".join(fields[4:]))
    return values


def normalize_record_value(record_type: str, value: str) -> str:
    kind = record_type.upper()
    cleaned = " ".join(value.split())
    if kind in {"A", "AAAA"}:
        return str(ipaddress.ip_address(cleaned))
    if kind in {"NS", "CNAME", "PTR"}:
        return normalize_name(cleaned)
    if kind == "DS":
        return cleaned.upper()
    return cleaned


def validate_ip(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{field} must be a string IP address")
    try:
        return str(ipaddress.ip_address(value.strip()))
    except ValueError as exc:
        raise ValueError(f"{field} must be a valid IP address") from exc


def load_contract(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read DNS verification contract {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError("contract must be a JSON object")

    zone = data.get("zone")
    if not isinstance(zone, str):
        raise ValueError("zone must be a multi-label DNS name")
    data["zone"] = normalize_name(zone, allow_underscore=False)
    if len(data["zone"].rstrip(".").split(".")) < 2:
        raise ValueError("zone must be a multi-label DNS name")
    data["primary"] = validate_ip(data.get("primary"), "primary")
    data["secondary"] = validate_ip(data.get("secondary"), "secondary")
    if data["primary"] == data["secondary"]:
        raise ValueError("primary and secondary must be different addresses")

    probe = data.get("authoritative_probe")
    if not isinstance(probe, dict):
        raise ValueError("authoritative_probe must be an object")
    probe_name = probe.get("name")
    probe_type = probe.get("type")
    if not isinstance(probe_name, str) or not isinstance(probe_type, str):
        raise ValueError("authoritative_probe requires string name and type")
    probe["name"] = normalize_name(probe_name)
    probe["type"] = probe_type.upper()
    if not probe["name"].endswith(data["zone"]):
        raise ValueError("authoritative_probe.name must be inside zone")
    expected = probe.get("expected_values", [])
    if not isinstance(expected, list) or not all(isinstance(value, str) and value for value in expected):
        raise ValueError("authoritative_probe.expected_values must be a list of non-empty strings")

    recursion = data.get("recursion_probe", {"name": "example.org.", "type": "A"})
    if not isinstance(recursion, dict) or not isinstance(recursion.get("name"), str) or not isinstance(recursion.get("type"), str):
        raise ValueError("recursion_probe requires string name and type")
    recursion["name"] = normalize_name(recursion["name"])
    recursion["type"] = recursion["type"].upper()
    data["recursion_probe"] = recursion

    nonexistent_name = data.get("nonexistent_name", f"_dns-verification-nonexistent.{data['zone']}")
    if not isinstance(nonexistent_name, str):
        raise ValueError("nonexistent_name must be a DNS name")
    data["nonexistent_name"] = normalize_name(nonexistent_name)
    if not data["nonexistent_name"].endswith(data["zone"]):
        raise ValueError("nonexistent_name must be inside zone")

    delegation = data.get("delegation")
    if delegation is not None:
        if not isinstance(delegation, dict):
            raise ValueError("delegation must be an object")
        delegation["resolver"] = validate_ip(delegation.get("resolver"), "delegation.resolver")
        nameservers = delegation.get("nameservers")
        if not isinstance(nameservers, list) or not nameservers:
            raise ValueError("delegation.nameservers must be a non-empty list")
        delegation["nameservers"] = sorted(normalize_name(value, allow_underscore=False) for value in nameservers if isinstance(value, str))
        if len(delegation["nameservers"]) != len(nameservers):
            raise ValueError("delegation.nameservers must contain only DNS names")
        require_ds = delegation.get("require_ds", True)
        if not isinstance(require_ds, bool):
            raise ValueError("delegation.require_ds must be boolean")
        delegation["require_ds"] = require_ds
        expected_ds = delegation.get("expected_ds", [])
        if not isinstance(expected_ds, list) or not all(isinstance(value, str) and value.strip() for value in expected_ds):
            raise ValueError("delegation.expected_ds must be a list of non-empty strings")
        delegation["expected_ds"] = sorted(value.strip() for value in expected_ds)

    timeout = data.get("secondary_sync_timeout_seconds", 180)
    if isinstance(timeout, bool) or not isinstance(timeout, int) or timeout < 1 or timeout > 3600:
        raise ValueError("secondary_sync_timeout_seconds must be an integer between 1 and 3600")
    return data


class Dig:
    def __init__(self, binary: str, timeout: int = 15):
        self.binary = binary
        self.timeout = timeout

    def run(self, server: str, name: str, record_type: str, *options: str, key_file: Path | None = None) -> DigResult:
        command = [self.binary, f"@{server}", name, record_type, "+time=3", "+tries=1", "+comments", "+answer", "+authority"]
        if key_file is not None:
            command.extend(["-k", str(key_file)])
        command.extend(options)
        completed = subprocess.run(command, text=True, capture_output=True, timeout=self.timeout, check=False)
        return DigResult(completed.returncode, completed.stdout, completed.stderr)


def write_key_file(algorithm: str, name: str, secret: str) -> Path:
    if not re.fullmatch(r"hmac-sha(1|224|256|384|512)", algorithm):
        raise ValueError("unsupported TSIG algorithm")
    key_name = normalize_name(name)
    cleaned_secret = secret.strip()
    if not cleaned_secret:
        raise ValueError("TSIG secret is empty")
    try:
        base64.b64decode(cleaned_secret, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("TSIG secret must be valid Base64") from exc
    handle = tempfile.NamedTemporaryFile("w", prefix="dns-tsig-", suffix=".key", delete=False)
    os.chmod(handle.name, 0o600)
    handle.write(f'key "{key_name}" {{\n  algorithm {algorithm};\n  secret "{cleaned_secret}";\n}};\n')
    handle.close()
    return Path(handle.name)


def require_authoritative(result: DigResult, server: str, context: str) -> list[str]:
    errors: list[str] = []
    if result.returncode != 0:
        errors.append(f"{server} {context}: dig exited {result.returncode}: {result.stderr.strip()}")
    if result.status != "NOERROR":
        errors.append(f"{server} {context}: expected NOERROR, got {result.status or 'no status'}")
    if "aa" not in result.flags:
        errors.append(f"{server} {context}: authoritative AA flag is missing")
    return errors


def check_authoritative_probe(dig: Dig, server: str, probe: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    try:
        expected_values = sorted(normalize_record_value(probe["type"], value) for value in probe.get("expected_values", []))
    except ValueError as exc:
        return [f"authoritative probe has invalid expected value: {exc}"]
    for transport in ("udp", "tcp"):
        options = ("+norecurse", "+tcp") if transport == "tcp" else ("+norecurse", "+notcp")
        result = dig.run(server, probe["name"], probe["type"], *options)
        context = f"{transport} {probe['name']} {probe['type']}"
        errors.extend(require_authoritative(result, server, context))
        try:
            values = sorted(normalize_record_value(probe["type"], value) for value in record_values(result.answer_lines, probe["name"], probe["type"]))
        except ValueError as exc:
            errors.append(f"{server} {context}: invalid answer value: {exc}")
            values = []
        if expected_values and values != expected_values:
            errors.append(f"{server} {context}: values {values}, expected {expected_values}")
        if not values:
            errors.append(f"{server} {context}: answer record is missing")
    return errors


def check_dnssec(dig: Dig, server: str, zone: str) -> list[str]:
    result = dig.run(server, zone, "DNSKEY", "+norecurse", "+dnssec", "+tcp")
    errors = require_authoritative(result, server, "DNSKEY DNSSEC")
    types = record_types(result.answer_lines)
    if "DNSKEY" not in types:
        errors.append(f"{server} DNSKEY DNSSEC: DNSKEY record is missing")
    if "RRSIG" not in types:
        errors.append(f"{server} DNSKEY DNSSEC: RRSIG record is missing")
    return errors


def check_no_recursion(dig: Dig, server: str, probe: dict[str, str]) -> list[str]:
    result = dig.run(server, probe["name"], probe["type"], "+recurse", "+notcp")
    errors: list[str] = []
    if "ra" in result.flags:
        errors.append(f"{server} recursion probe: RA flag must not be present")
    if result.answer_lines:
        errors.append(f"{server} recursion probe: recursive answer must be empty")
    if result.status not in {"REFUSED", "SERVFAIL"}:
        errors.append(f"{server} recursion probe: expected REFUSED or SERVFAIL, got {result.status or 'no status'}")
    return errors


def check_authoritative_nxdomain(dig: Dig, server: str, zone: str, name: str) -> list[str]:
    result = dig.run(server, name, "A", "+norecurse", "+dnssec", "+tcp")
    errors: list[str] = []
    if result.returncode != 0:
        errors.append(f"{server} NXDOMAIN: dig exited {result.returncode}: {result.stderr.strip()}")
    if result.status != "NXDOMAIN":
        errors.append(f"{server} NXDOMAIN: expected NXDOMAIN, got {result.status or 'no status'}")
    if "aa" not in result.flags:
        errors.append(f"{server} NXDOMAIN: authoritative AA flag is missing")
    if result.answer_lines:
        errors.append(f"{server} NXDOMAIN: answer section must be empty")
    authority_types = record_types(result.authority_lines)
    if "SOA" not in authority_types:
        errors.append(f"{server} NXDOMAIN: SOA authority record is missing")
    if "RRSIG" not in authority_types:
        errors.append(f"{server} NXDOMAIN: RRSIG authority record is missing")
    try:
        parse_soa_serial(result.authority_lines, zone)
    except ValueError as exc:
        errors.append(f"{server} NXDOMAIN: {exc}")
    return errors


def check_delegation(dig: Dig, zone: str, delegation: dict[str, Any]) -> list[str]:
    resolver = delegation["resolver"]
    errors: list[str] = []
    ns_result = dig.run(resolver, zone, "NS", "+recurse", "+dnssec", "+tcp")
    if ns_result.returncode != 0 or ns_result.status != "NOERROR":
        errors.append(f"delegation NS via {resolver}: query failed with {ns_result.status or ns_result.returncode}")
    actual_ns = sorted(normalize_record_value("NS", value) for value in record_values(ns_result.answer_lines, zone, "NS"))
    if actual_ns != delegation["nameservers"]:
        errors.append(f"delegation NS via {resolver}: values {actual_ns}, expected {delegation['nameservers']}")

    ds_result = dig.run(resolver, zone, "DS", "+recurse", "+dnssec", "+tcp")
    if ds_result.returncode != 0 or ds_result.status != "NOERROR":
        errors.append(f"delegation DS via {resolver}: query failed with {ds_result.status or ds_result.returncode}")
    actual_ds = sorted(normalize_record_value("DS", value) for value in record_values(ds_result.answer_lines, zone, "DS"))
    if delegation["require_ds"] and not actual_ds:
        errors.append(f"delegation DS via {resolver}: DS record is missing")
    expected_ds = sorted(normalize_record_value("DS", value) for value in delegation["expected_ds"])
    if expected_ds and actual_ds != expected_ds:
        errors.append(f"delegation DS via {resolver}: values {actual_ds}, expected {expected_ds}")
    return errors


def axfr_succeeded(result: DigResult, zone: str) -> bool:
    soa_count = 0
    expected = normalize_name(zone)
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 4 and normalize_name(fields[0]) == expected and fields[3].upper() == "SOA":
            soa_count += 1
    return result.returncode == 0 and soa_count >= 2 and "Transfer failed" not in result.stdout


def check_unauthenticated_axfr_denied(dig: Dig, server: str, zone: str) -> list[str]:
    result = dig.run(server, zone, "AXFR", "+tcp")
    return [] if not axfr_succeeded(result, zone) else [f"{server}: unauthenticated AXFR unexpectedly succeeded"]


def check_authenticated_primary_axfr(dig: Dig, server: str, zone: str, key_file: Path) -> list[str]:
    result = dig.run(server, zone, "AXFR", "+tcp", key_file=key_file)
    if axfr_succeeded(result, zone):
        return []
    detail = result.stderr.strip()
    if not detail:
        output_lines = result.stdout.strip().splitlines()
        detail = output_lines[-1] if output_lines else "no output"
    return [f"{server}: authenticated AXFR failed: {detail}"]


def soa_serial(dig: Dig, server: str, zone: str) -> tuple[int | None, list[str]]:
    result = dig.run(server, zone, "SOA", "+norecurse", "+tcp")
    errors = require_authoritative(result, server, "SOA")
    if errors:
        return None, errors
    try:
        return parse_soa_serial(result.answer_lines, zone), []
    except ValueError as exc:
        return None, [f"{server} SOA: {exc}"]


def wait_for_serial_match(dig: Dig, primary: str, secondary: str, zone: str, timeout: int) -> list[str]:
    deadline = time.monotonic() + timeout
    last_primary: int | None = None
    last_secondary: int | None = None
    last_errors: list[str] = []
    while time.monotonic() < deadline:
        last_primary, primary_errors = soa_serial(dig, primary, zone)
        last_secondary, secondary_errors = soa_serial(dig, secondary, zone)
        last_errors = primary_errors + secondary_errors
        if not last_errors and last_primary == last_secondary:
            return []
        time.sleep(2)
    detail = f"primary={last_primary}, secondary={last_secondary}"
    if last_errors:
        detail += "; " + "; ".join(last_errors)
    return [f"SOA serials did not match before timeout: {detail}"]


def verify(contract: dict[str, Any], dig: Dig, secret: str | None) -> list[str]:
    errors: list[str] = []
    zone = contract["zone"]
    primary = contract["primary"]
    secondary = contract["secondary"]
    for server in (primary, secondary):
        errors.extend(check_authoritative_probe(dig, server, contract["authoritative_probe"]))
        errors.extend(check_dnssec(dig, server, zone))
        errors.extend(check_authoritative_nxdomain(dig, server, zone, contract["nonexistent_name"]))
        errors.extend(check_no_recursion(dig, server, contract["recursion_probe"]))
        errors.extend(check_unauthenticated_axfr_denied(dig, server, zone))

    if contract.get("delegation") is not None:
        errors.extend(check_delegation(dig, zone, contract["delegation"]))

    errors.extend(wait_for_serial_match(dig, primary, secondary, zone, contract["secondary_sync_timeout_seconds"]))

    tsig = contract.get("transfer_tsig")
    if tsig is not None:
        if not isinstance(tsig, dict):
            errors.append("transfer_tsig must be an object")
        elif secret is None:
            errors.append("transfer TSIG is configured but the secret environment variable is unset")
        else:
            key_file: Path | None = None
            try:
                key_file = write_key_file(
                    str(tsig.get("algorithm", "hmac-sha256")),
                    str(tsig.get("name", "")),
                    secret,
                )
                errors.extend(check_authenticated_primary_axfr(dig, primary, zone, key_file))
            except ValueError as exc:
                errors.append(str(exc))
            finally:
                if key_file is not None:
                    key_file.unlink(missing_ok=True)
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--dig", default="dig", help="dig executable")
    parser.add_argument("--tsig-secret-env", default="DNS_TRANSFER_TSIG_SECRET")
    args = parser.parse_args()

    try:
        contract = load_contract(args.contract)
        errors = verify(contract, Dig(args.dig), os.getenv(args.tsig_secret_env))
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        print(f"DNS verification error: {exc}", file=sys.stderr)
        return 2

    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("OK: primary and secondary authoritative DNS verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
