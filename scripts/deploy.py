#!/usr/bin/env python3
"""Deploy an OPNsense VM and apply its global router configuration."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_RUNTIME_DIR = ROOT / ".router"
REMOTE_BOOTSTRAP = "/tmp/router-bootstrap.py"


class DeployError(RuntimeError):
    """Raised when a deployment stage cannot complete safely."""


def run(
    command: list[str],
    *,
    cwd: pathlib.Path | None = None,
    env: dict[str, str] | None = None,
    input_text: str | None = None,
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        input=input_text,
        text=True,
        capture_output=capture,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() if capture else ""
        raise DeployError(f"Command failed ({result.returncode}): {' '.join(command)} {detail}")
    return result


def atomic_write(path: pathlib.Path, content: str, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        handle.write(content)
        handle.flush()
        os.fchmod(handle.fileno(), mode)
        temporary = pathlib.Path(handle.name)
    temporary.replace(path)
    os.chmod(path, mode)


def tofu_output(directory: pathlib.Path, name: str) -> str:
    result = run(
        ["tofu", f"-chdir={directory}", "output", "-raw", name],
        capture=True,
    )
    value = result.stdout.strip()
    if not value:
        raise DeployError(f"OpenTofu output {name!r} is empty")
    return value


def ssh_options(key: pathlib.Path, known_hosts: pathlib.Path) -> list[str]:
    return [
        "-i",
        str(key),
        "-o",
        "BatchMode=yes",
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "ConnectTimeout=5",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        f"UserKnownHostsFile={known_hosts}",
    ]


def wait_for_ssh(
    host: str,
    username: str,
    key: pathlib.Path,
    known_hosts: pathlib.Path,
    timeout: int,
) -> None:
    deadline = time.monotonic() + timeout
    target = f"{username}@{host}"
    last_error = ""
    while time.monotonic() < deadline:
        result = subprocess.run(
            ["ssh", *ssh_options(key, known_hosts), target, "true"],
            text=True,
            capture_output=True,
        )
        if result.returncode == 0:
            return
        last_error = result.stderr.strip()
        time.sleep(3)
    raise DeployError(f"SSH did not become ready for {target}: {last_error}")


def load_credentials(path: pathlib.Path) -> dict[str, str] | None:
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise DeployError(f"Unable to read credentials file {path}: {exc}") from exc
    key = str(data.get("key", "")).strip()
    secret = str(data.get("secret", "")).strip()
    if not key or not secret:
        raise DeployError(f"Credentials file {path} is incomplete")
    return {"key": key, "secret": secret}


def copy_bootstrap(
    host: str,
    username: str,
    key: pathlib.Path,
    known_hosts: pathlib.Path,
) -> None:
    target = f"{username}@{host}:{REMOTE_BOOTSTRAP}"
    run(
        [
            "scp",
            *ssh_options(key, known_hosts),
            str(ROOT / "scripts" / "router-bootstrap.py"),
            target,
        ]
    )


def run_bootstrap(
    host: str,
    username: str,
    key: pathlib.Path,
    known_hosts: pathlib.Path,
    config: dict[str, Any],
) -> dict[str, Any]:
    copy_bootstrap(host, username, key, known_hosts)
    target = f"{username}@{host}"
    command = [
        "ssh",
        *ssh_options(key, known_hosts),
        target,
        "sudo",
        "-n",
        "/usr/local/bin/python3",
        REMOTE_BOOTSTRAP,
    ]
    try:
        result = run(command, input_text=json.dumps(config), capture=True)
        response = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise DeployError("Router bootstrap returned invalid JSON") from exc
    finally:
        subprocess.run(
            [
                "ssh",
                *ssh_options(key, known_hosts),
                target,
                "rm",
                "-f",
                REMOTE_BOOTSTRAP,
            ],
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    required = ["uri", "key", "secret", "ca_certificate", "ca_uuid", "ca_ref_id"]
    missing = [name for name in required if not str(response.get(name, "")).strip()]
    if missing:
        raise DeployError("Router bootstrap response is missing: " + ", ".join(missing))
    return response


def persist_bootstrap_result(
    result: dict[str, Any], credentials_file: pathlib.Path, ca_file: pathlib.Path
) -> dict[str, str]:
    ca_certificate = str(result["ca_certificate"])
    atomic_write(ca_file, ca_certificate, 0o600)
    credentials = {
        key: value
        for key, value in result.items()
        if key != "ca_certificate"
    }
    credentials["ca_file"] = str(ca_file.resolve())
    atomic_write(
        credentials_file,
        json.dumps(credentials, indent=2, sort_keys=True) + "\n",
        0o600,
    )
    return {
        "OPNSENSE_URI": str(result["uri"]),
        "OPNSENSE_API_KEY": str(result["key"]),
        "OPNSENSE_API_SECRET": str(result["secret"]),
        "OPNSENSE_ALLOW_INSECURE": "false",
        "SSL_CERT_FILE": str(ca_file.resolve()),
    }


def apply_global_config(directory: pathlib.Path, environment: dict[str, str], auto_approve: bool) -> None:
    env = os.environ.copy()
    env.update(environment)
    run(["tofu", f"-chdir={directory}", "init", "-input=false"], env=env)
    state = subprocess.run(
        ["tofu", f"-chdir={directory}", "state", "list"],
        env=env,
        text=True,
        capture_output=True,
    )
    if state.returncode != 0 and "No state file was found" not in state.stderr:
        raise DeployError(f"Unable to read global state: {state.stderr.strip()}")
    if "opnsense_caddy_settings.main" not in state.stdout.splitlines():
        run(
            [
                "tofu",
                f"-chdir={directory}",
                "import",
                "-input=false",
                "opnsense_caddy_settings.main",
                "caddy_settings",
            ],
            env=env,
        )
    command = ["tofu", f"-chdir={directory}", "apply"]
    if auto_approve:
        command.extend(["-auto-approve", "-input=false"])
    run(command, env=env)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ssh-private-key",
        type=pathlib.Path,
        default=os.environ.get("ROUTER_SSH_PRIVATE_KEY"),
        required=os.environ.get("ROUTER_SSH_PRIVATE_KEY") is None,
    )
    parser.add_argument("--credentials-file", type=pathlib.Path, default=DEFAULT_RUNTIME_DIR / "credentials.json")
    parser.add_argument("--ca-file", type=pathlib.Path, default=DEFAULT_RUNTIME_DIR / "ca.pem")
    parser.add_argument("--known-hosts-file", type=pathlib.Path, default=DEFAULT_RUNTIME_DIR / "known_hosts")
    parser.add_argument("--vm-directory", type=pathlib.Path, default=ROOT / "tofu")
    parser.add_argument("--global-directory", type=pathlib.Path, default=ROOT / "router")
    parser.add_argument("--management-interface", default="lan")
    parser.add_argument("--webui-port", type=int, default=10443)
    parser.add_argument("--ca-name", default="biptec.net")
    parser.add_argument("--ca-country", default="NL")
    parser.add_argument("--ca-key-type", default="4096")
    parser.add_argument("--ca-digest", default="sha256")
    parser.add_argument("--ca-lifetime-days", type=int, default=3650)
    parser.add_argument("--certificate-key-type", default="2048")
    parser.add_argument("--certificate-lifetime-days", type=int, default=3650)
    parser.add_argument("--ssh-timeout-seconds", type=int, default=300)
    parser.add_argument("--auto-approve", action="store_true")
    parser.add_argument("--skip-vm-apply", action="store_true")
    parser.add_argument("--skip-global-apply", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        key = pathlib.Path(args.ssh_private_key).expanduser().resolve()
        if not key.is_file():
            raise DeployError(f"SSH private key does not exist: {key}")
        args.known_hosts_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        args.known_hosts_file.touch(mode=0o600, exist_ok=True)
        os.chmod(args.known_hosts_file, 0o600)

        if not args.skip_vm_apply:
            command = ["tofu", f"-chdir={args.vm_directory}", "apply"]
            if args.auto_approve:
                command.extend(["-auto-approve", "-input=false"])
            run(command)

        host = tofu_output(args.vm_directory, "management_ip")
        username = tofu_output(args.vm_directory, "cloudinit_username")
        fqdn = tofu_output(args.vm_directory, "management_fqdn")
        wait_for_ssh(host, username, key, args.known_hosts_file, args.ssh_timeout_seconds)
        bootstrap_config = {
            "api_username": username,
            "credentials": load_credentials(args.credentials_file),
            "management_interface": args.management_interface,
            "management_ip": host,
            "management_fqdn": fqdn,
            "webui_port": args.webui_port,
            "ca_name": args.ca_name,
            "ca_country": args.ca_country,
            "ca_key_type": args.ca_key_type,
            "ca_digest": args.ca_digest,
            "ca_lifetime_days": args.ca_lifetime_days,
            "certificate_key_type": args.certificate_key_type,
            "certificate_lifetime_days": args.certificate_lifetime_days,
        }
        result = run_bootstrap(
            host,
            username,
            key,
            args.known_hosts_file,
            bootstrap_config,
        )
        environment = persist_bootstrap_result(result, args.credentials_file, args.ca_file)
        if not args.skip_global_apply:
            apply_global_config(args.global_directory, environment, args.auto_approve)
        print(f"Router ready: {result['uri']}")
        print(f"Credentials: {args.credentials_file}")
        print(f"CA certificate: {args.ca_file}")
        return 0
    except (DeployError, OSError, ValueError) as exc:
        print(f"deployment failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
