#!/bin/sh
set -eu

TOFU_BIN=${TOFU_BIN:-tofu}
STATE_PATH=${STATE_PATH:-terraform.tfstate}
VAR_FILE=${VAR_FILE:-terraform.tfvars}

if [ ! -f "$VAR_FILE" ]; then
    echo "Variable file not found: $VAR_FILE" >&2
    exit 1
fi

import_if_missing() {
    address=$1
    id=$2
    if "$TOFU_BIN" state show -state="$STATE_PATH" "$address" >/dev/null 2>&1; then
        echo "Already owned: $address"
        return
    fi
    echo "Importing: $address"
    "$TOFU_BIN" import -input=false -state="$STATE_PATH" -var-file="$VAR_FILE" "$address" "$id"
}

import_if_missing 'module.router_foundation.opnsense_system_webgui.management' system_webgui
import_if_missing 'module.router_foundation.opnsense_system_ssh.management' system_ssh
import_if_missing 'module.router_services.opnsense_bind_settings.main' bind_settings
import_if_missing 'module.router_services.opnsense_caddy_settings.main' caddy_settings
