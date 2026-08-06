#!/usr/bin/env python3
"""Verify exact OPNsense listener ownership from FreeBSD sockstat output."""

from __future__ import annotations

import argparse
import ipaddress
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SUPPORTED_PROTOCOLS = {"tcp4", "udp4", "tcp6", "udp6"}


@dataclass(frozen=True)
class Socket:
    process: str
    protocol: str
    address: str
    port: int


@dataclass(frozen=True)
class Endpoint:
    protocol: str
    address: str
    port: int


def parse_local(value: str) -> tuple[str, int]:
    try:
        address, port_text = value.rsplit(":", 1)
        port = int(port_text)
    except (ValueError, TypeError) as exc:
        raise ValueError(f"invalid local socket address {value!r}") from exc
    return address.strip("[]"), port


def parse_sockstat(output: str) -> list[Socket]:
    sockets: list[Socket] = []
    for raw_line in output.splitlines():
        fields = raw_line.split()
        if len(fields) < 6 or fields[0].upper() == "USER":
            continue
        protocol = fields[4].lower()
        if protocol not in SUPPORTED_PROTOCOLS:
            continue
        try:
            address, port = parse_local(fields[5])
        except ValueError:
            continue
        sockets.append(Socket(fields[1], protocol, address, port))
    return sockets


def require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} must be a non-empty string")
    return value.strip()


def require_port(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 65535:
        raise ValueError(f"{field} must be an integer between 1 and 65535")
    return value


def load_contract(path: Path) -> dict[Endpoint, set[str]]:
    try:
        document = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read listener contract {path}: {exc}") from exc

    listeners = document.get("listeners") if isinstance(document, dict) else None
    if not isinstance(listeners, list) or not listeners:
        raise ValueError("contract.listeners must be a non-empty list")

    expected: dict[Endpoint, set[str]] = {}
    for index, listener in enumerate(listeners):
        prefix = f"listeners[{index}]"
        if not isinstance(listener, dict):
            raise ValueError(f"{prefix} must be an object")
        require_string(listener.get("name"), f"{prefix}.name")

        processes = listener.get("processes")
        protocols = listener.get("protocols")
        addresses = listener.get("addresses")
        ports = listener.get("ports")
        if not isinstance(processes, list) or not processes:
            raise ValueError(f"{prefix}.processes must be a non-empty list")
        if not isinstance(protocols, list) or not protocols:
            raise ValueError(f"{prefix}.protocols must be a non-empty list")
        if not isinstance(addresses, list) or not addresses:
            raise ValueError(f"{prefix}.addresses must be a non-empty list")
        if not isinstance(ports, list) or not ports:
            raise ValueError(f"{prefix}.ports must be a non-empty list")

        allowed_processes = {require_string(value, f"{prefix}.processes") for value in processes}
        checked_protocols = {require_string(value, f"{prefix}.protocols").lower() for value in protocols}
        unknown_protocols = checked_protocols - SUPPORTED_PROTOCOLS
        if unknown_protocols:
            raise ValueError(f"{prefix}.protocols contains unsupported values: {sorted(unknown_protocols)}")

        checked_addresses: set[str] = set()
        for value in addresses:
            address = require_string(value, f"{prefix}.addresses")
            if address == "*":
                raise ValueError(f"{prefix}.addresses cannot contain wildcard listeners")
            try:
                checked_addresses.add(str(ipaddress.ip_address(address)))
            except ValueError as exc:
                raise ValueError(f"{prefix}.addresses contains invalid IP {address!r}") from exc

        checked_ports = {require_port(value, f"{prefix}.ports") for value in ports}
        for protocol in checked_protocols:
            family = 6 if protocol.endswith("6") else 4
            for address in checked_addresses:
                if ipaddress.ip_address(address).version != family:
                    raise ValueError(f"{prefix}: {protocol} does not match address family of {address}")
                for port in checked_ports:
                    endpoint = Endpoint(protocol, address, port)
                    if endpoint in expected:
                        raise ValueError(f"duplicate endpoint in listener contract: {endpoint}")
                    expected[endpoint] = allowed_processes
    return expected


def verify(expected: dict[Endpoint, set[str]], sockets: list[Socket]) -> list[str]:
    managed_pairs = {(endpoint.protocol, endpoint.port) for endpoint in expected}
    actual: dict[Endpoint, set[str]] = {}
    for socket in sockets:
        if (socket.protocol, socket.port) not in managed_pairs:
            continue
        endpoint = Endpoint(socket.protocol, socket.address, socket.port)
        actual.setdefault(endpoint, set()).add(socket.process)

    errors: list[str] = []
    for endpoint, allowed_processes in sorted(expected.items(), key=lambda item: (item[0].port, item[0].protocol, item[0].address)):
        processes = actual.get(endpoint, set())
        if not processes:
            errors.append(f"missing listener {endpoint.protocol} {endpoint.address}:{endpoint.port}")
            continue
        unexpected = processes - allowed_processes
        if unexpected:
            errors.append(
                f"unexpected process on {endpoint.protocol} {endpoint.address}:{endpoint.port}: "
                f"{sorted(unexpected)}; allowed {sorted(allowed_processes)}"
            )

    for endpoint, processes in sorted(actual.items(), key=lambda item: (item[0].port, item[0].protocol, item[0].address)):
        if endpoint not in expected:
            errors.append(
                f"unexpected listener {endpoint.protocol} {endpoint.address}:{endpoint.port} "
                f"owned by {sorted(processes)}"
            )
    return errors


def read_sockstat(input_path: Path | None) -> str:
    if input_path is not None:
        return input_path.read_text()
    result = subprocess.run(
        ["/usr/bin/sockstat", "-4", "-6", "-l"],
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True, help="JSON listener contract")
    parser.add_argument("--input", type=Path, help="Read sockstat output from a file instead of executing sockstat")
    args = parser.parse_args()

    try:
        expected = load_contract(args.contract)
        sockets = parse_sockstat(read_sockstat(args.input))
        errors = verify(expected, sockets)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f"listener verification error: {exc}", file=sys.stderr)
        return 2

    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1

    print(f"OK: verified {len(expected)} exact listener endpoints")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
