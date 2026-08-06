#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_CONFIG=${BUILD_CONFIG:-$ROOT_DIR/image/source-revisions.env}

if [ -f "$BUILD_CONFIG" ]; then
    # shellcheck source=/dev/null
    . "$BUILD_CONFIG"
fi

TOOLS_DIR=${TOOLS_DIR:-/usr/tools}
BUILD_ROOT=${BUILD_ROOT:-$(dirname "$TOOLS_DIR")}
CORE_DIR=${CORE_DIR:-$BUILD_ROOT/core}
PLUGINS_DIR=${PLUGINS_DIR:-$BUILD_ROOT/plugins}
PORTS_DIR=${PORTS_DIR:-$BUILD_ROOT/ports}
SRC_DIR=${SRC_DIR:-$BUILD_ROOT/src}
BUILD_MANIFEST=${BUILD_MANIFEST:-$ROOT_DIR/image/build-manifest.json}

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

fail()
{
    echo "$*" >&2
    exit 1
}

require_commit()
{
    name=$1
    value=$2
    printf '%s\n' "$value" | grep -Eq '^[0-9a-f]{40}$' ||
        fail "$name must be an exact 40-character lowercase Git commit SHA"
}

require_safe_value()
{
    name=$1
    value=$2
    case "$value" in
        *[!A-Za-z0-9._/:+-]*) fail "$name contains unsupported characters" ;;
    esac
}

verify_repository()
{
    label=$1
    path=$2
    expected_commit=$3
    expected_branch=$4

    git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        fail "$label repository not found: $path"

    actual_commit=$(git -C "$path" rev-parse HEAD)
    [ "$actual_commit" = "$expected_commit" ] ||
        fail "$label commit mismatch: expected $expected_commit, found $actual_commit"

    actual_branch=$(git -C "$path" rev-parse --abbrev-ref HEAD)
    [ "$actual_branch" = "$expected_branch" ] ||
        fail "$label branch mismatch: expected $expected_branch, found $actual_branch"

    [ -z "$(git -C "$path" status --porcelain --untracked-files=all)" ] ||
        fail "$label repository is not clean: $path"
}

for name in TOOLS_COMMIT CORE_COMMIT PLUGINS_COMMIT PORTS_COMMIT SRC_COMMIT; do
    eval "value=\${$name:-}"
    require_commit "$name" "$value"
done

for name in OPNSENSE_VERSION NAME TYPE GITPREFIX TOOLSBRANCH COREBRANCH PLUGINSBRANCH PORTSBRANCH SRCBRANCH IMAGE_SIZE IMAGE_SWAP; do
    eval "value=\${$name}"
    require_safe_value "$name" "$value"
done

verify_repository tools "$TOOLS_DIR" "$TOOLS_COMMIT" "$TOOLSBRANCH"
verify_repository core "$CORE_DIR" "$CORE_COMMIT" "$COREBRANCH"
verify_repository ports "$PORTS_DIR" "$PORTS_COMMIT" "$PORTSBRANCH"
verify_repository src "$SRC_DIR" "$SRC_COMMIT" "$SRCBRANCH"

git -C "$PLUGINS_DIR" cat-file -e "$PLUGINS_COMMIT^{commit}" 2>/dev/null ||
    fail "plugins commit is not available in $PLUGINS_DIR: $PLUGINS_COMMIT"

PLUGIN_SNAPSHOT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opnsense-plugin-snapshot.XXXXXX")
MANIFEST_TMP="$BUILD_MANIFEST.tmp.$$"
cleanup()
{
    rm -rf "$PLUGIN_SNAPSHOT_DIR"
    rm -f "$MANIFEST_TMP"
}
trap cleanup EXIT INT TERM

snapshot_plugin()
{
    source_path=$1
    git -C "$PLUGINS_DIR" archive "$PLUGINS_COMMIT" "$source_path" |
        tar -x -C "$PLUGIN_SNAPSHOT_DIR"
    snapshot_path=$PLUGIN_SNAPSHOT_DIR/$source_path
    [ -f "$snapshot_path/Makefile" ] ||
        fail "plugin snapshot is missing Makefile: $source_path"
    printf '%s\n' "$snapshot_path"
}

QEMU_PLUGIN_DIR=$(snapshot_plugin emulators/qemu-guest-agent)
API_EXTENSIONS_PLUGIN_DIR=$(snapshot_plugin sysutils/api-extensions)
BIND_PLUGIN_DIR=$(snapshot_plugin dns/bind)
CADDY_PLUGIN_DIR=$(snapshot_plugin www/caddy)
NOCLOUD_PLUGIN_DIR=$ROOT_DIR/guest/nocloud-bootstrap
CADDY_POLICY_DIR=$ROOT_DIR/guest/caddy-policy

export NAME TYPE GITBASE GITPREFIX TOOLSBRANCH COREBRANCH PLUGINSBRANCH PORTSBRANCH SRCBRANCH
export VERSION="$OPNSENSE_VERSION"

make -C "$TOOLS_DIR" \
    "custom-vm,qcow2,$IMAGE_SIZE,$IMAGE_SWAP,proxmox" \
    ADDITIONS="$QEMU_PLUGIN_DIR $API_EXTENSIONS_PLUGIN_DIR $BIND_PLUGIN_DIR $CADDY_PLUGIN_DIR $NOCLOUD_PLUGIN_DIR $CADDY_POLICY_DIR"

verify_repository tools "$TOOLS_DIR" "$TOOLS_COMMIT" "$TOOLSBRANCH"
verify_repository core "$CORE_DIR" "$CORE_COMMIT" "$COREBRANCH"
verify_repository ports "$PORTS_DIR" "$PORTS_COMMIT" "$PORTSBRANCH"
verify_repository src "$SRC_DIR" "$SRC_COMMIT" "$SRCBRANCH"

mkdir -p "$(dirname "$BUILD_MANIFEST")"
cat > "$MANIFEST_TMP" <<EOF_MANIFEST
{
  "schema_version": 1,
  "opnsense_version": "$OPNSENSE_VERSION",
  "image": {
    "size": "$IMAGE_SIZE",
    "swap": "$IMAGE_SWAP",
    "profile": "proxmox"
  },
  "sources": {
    "tools": {"branch": "$TOOLSBRANCH", "commit": "$TOOLS_COMMIT"},
    "core": {"branch": "$COREBRANCH", "commit": "$CORE_COMMIT"},
    "plugins": {"branch": "$PLUGINSBRANCH", "commit": "$PLUGINS_COMMIT"},
    "ports": {"branch": "$PORTSBRANCH", "commit": "$PORTS_COMMIT"},
    "src": {"branch": "$SRCBRANCH", "commit": "$SRC_COMMIT"}
  },
  "plugin_paths": [
    "emulators/qemu-guest-agent",
    "sysutils/api-extensions",
    "dns/bind",
    "www/caddy",
    "guest/nocloud-bootstrap",
    "guest/caddy-policy"
  ]
}
EOF_MANIFEST
mv "$MANIFEST_TMP" "$BUILD_MANIFEST"
trap - EXIT INT TERM
rm -rf "$PLUGIN_SNAPSHOT_DIR"
