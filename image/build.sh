#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_DIR=${TOOLS_DIR:-/usr/tools}
IMAGE_SIZE=${IMAGE_SIZE:-20G}
IMAGE_SWAP=${IMAGE_SWAP:-never}

if [ ! -d "$TOOLS_DIR" ]; then
    echo "OPNsense tools directory not found: $TOOLS_DIR" >&2
    exit 1
fi

PLUGIN_DIR="$ROOT_DIR/guest/nocloud-bootstrap"

exec make -C "$TOOLS_DIR" \
    "custom-vm,qcow2,$IMAGE_SIZE,$IMAGE_SWAP,proxmox" \
    ADDITIONS="os-qemu-guest-agent $PLUGIN_DIR"
