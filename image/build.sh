#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_DIR=${TOOLS_DIR:-/usr/tools}
IMAGE_SIZE=${IMAGE_SIZE:-20G}
IMAGE_SWAP=${IMAGE_SWAP:-never}
OPNSENSE_VERSION=${OPNSENSE_VERSION:-${VERSION:-26.7.1}}
NAME=${NAME:-OPNsense}
TYPE=${TYPE:-opnsense}
GITBASE=${GITBASE:-https://github.com/biptec}
GITPREFIX=${GITPREFIX:-opnsense-}
TOOLSBRANCH=${TOOLSBRANCH:-master}
COREBRANCH=${COREBRANCH:-master}
PLUGINSBRANCH=${PLUGINSBRANCH:-master}
PORTSBRANCH=${PORTSBRANCH:-master}
SRCBRANCH=${SRCBRANCH:-master}

export NAME TYPE GITBASE GITPREFIX TOOLSBRANCH COREBRANCH PLUGINSBRANCH PORTSBRANCH SRCBRANCH
export VERSION="$OPNSENSE_VERSION"

if [ ! -d "$TOOLS_DIR" ]; then
    echo "OPNsense tools directory not found: $TOOLS_DIR" >&2
    exit 1
fi

PLUGIN_DIR="$ROOT_DIR/guest/nocloud-bootstrap"
CADDY_POLICY_DIR="$ROOT_DIR/guest/caddy-policy"

exec make -C "$TOOLS_DIR" \
    "custom-vm,qcow2,$IMAGE_SIZE,$IMAGE_SWAP,proxmox" \
    ADDITIONS="os-qemu-guest-agent os-caddy $PLUGIN_DIR $CADDY_POLICY_DIR"
