#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

create_repo()
{
    path=$1
    mkdir -p "$path"
    git -C "$path" init -q -b master
    git -C "$path" config user.name test
    git -C "$path" config user.email test@example.com
    printf '%s\n' "$(basename "$path") source" > "$path/source.txt"
    git -C "$path" add source.txt
    git -C "$path" commit -q -m initial
}

BUILD_ROOT="$TMPDIR/build-root"
for repo in tools core plugins ports src; do
    create_repo "$BUILD_ROOT/$repo"
done

for plugin in \
    emulators/qemu-guest-agent \
    sysutils/api-extensions \
    dns/bind \
    www/caddy; do
    mkdir -p "$BUILD_ROOT/plugins/$plugin"
    printf 'PLUGIN_NAME=%s\n' "$(basename "$plugin")" > "$BUILD_ROOT/plugins/$plugin/Makefile"
done
git -C "$BUILD_ROOT/plugins" add .
git -C "$BUILD_ROOT/plugins" commit -q -m plugins

TOOLS_COMMIT=$(git -C "$BUILD_ROOT/tools" rev-parse HEAD)
CORE_COMMIT=$(git -C "$BUILD_ROOT/core" rev-parse HEAD)
PLUGINS_COMMIT=$(git -C "$BUILD_ROOT/plugins" rev-parse HEAD)
PORTS_COMMIT=$(git -C "$BUILD_ROOT/ports" rev-parse HEAD)
SRC_COMMIT=$(git -C "$BUILD_ROOT/src" rev-parse HEAD)

cat > "$TMPDIR/source-revisions.env" <<EOF_REVISIONS
TOOLS_COMMIT=$TOOLS_COMMIT
CORE_COMMIT=$CORE_COMMIT
PLUGINS_COMMIT=$PLUGINS_COMMIT
PORTS_COMMIT=$PORTS_COMMIT
SRC_COMMIT=$SRC_COMMIT
TOOLSBRANCH=master
COREBRANCH=master
PLUGINSBRANCH=master
PORTSBRANCH=master
SRCBRANCH=master
EOF_REVISIONS

cat > "$TMPDIR/wrong-revisions.env" <<EOF_REVISIONS
TOOLS_COMMIT=0000000000000000000000000000000000000000
CORE_COMMIT=$CORE_COMMIT
PLUGINS_COMMIT=$PLUGINS_COMMIT
PORTS_COMMIT=$PORTS_COMMIT
SRC_COMMIT=$SRC_COMMIT
TOOLSBRANCH=master
COREBRANCH=master
PLUGINSBRANCH=master
PORTSBRANCH=master
SRCBRANCH=master
EOF_REVISIONS

mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/make" <<'EOF_MAKE'
#!/bin/sh
{
    printf 'NAME=%s\n' "$NAME"
    printf 'TYPE=%s\n' "$TYPE"
    printf 'VERSION=%s\n' "$VERSION"
    printf 'GITBASE=%s\n' "$GITBASE"
    printf 'GITPREFIX=%s\n' "$GITPREFIX"
    printf 'TOOLSBRANCH=%s\n' "$TOOLSBRANCH"
    printf 'COREBRANCH=%s\n' "$COREBRANCH"
    printf 'PLUGINSBRANCH=%s\n' "$PLUGINSBRANCH"
    printf 'PORTSBRANCH=%s\n' "$PORTSBRANCH"
    printf 'SRCBRANCH=%s\n' "$SRCBRANCH"
    printf '%s\n' "$@"

    additions=
    for argument in "$@"; do
        case "$argument" in
            ADDITIONS=*) additions=${argument#ADDITIONS=} ;;
        esac
    done
    [ -n "$additions" ]
    for addition in $additions; do
        [ -d "$addition" ]
        printf 'ADDITION=%s\n' "$addition"
    done
} > "$BUILD_TEST_OUTPUT"
EOF_MAKE
chmod 755 "$TMPDIR/bin/make"

MANIFEST="$TMPDIR/build-manifest.json"
BUILD_TEST_OUTPUT="$TMPDIR/arguments" \
BUILD_CONFIG="$TMPDIR/source-revisions.env" \
BUILD_MANIFEST="$MANIFEST" \
PATH="$TMPDIR/bin:$PATH" \
TOOLS_DIR="$BUILD_ROOT/tools" \
CORE_DIR="$BUILD_ROOT/core" \
PLUGINS_DIR="$BUILD_ROOT/plugins" \
PORTS_DIR="$BUILD_ROOT/ports" \
SRC_DIR="$BUILD_ROOT/src" \
IMAGE_SIZE="24G" \
IMAGE_SWAP="1G" \
"$ROOT_DIR/image/build.sh"

EXPECTED_NOCLOUD="$ROOT_DIR/guest/nocloud-bootstrap"
EXPECTED_CADDY_POLICY="$ROOT_DIR/guest/caddy-policy"
grep -Fx -- 'NAME=OPNsense' "$TMPDIR/arguments" >/dev/null
grep -Fx -- 'TYPE=opnsense' "$TMPDIR/arguments" >/dev/null
grep -Fx -- 'VERSION=26.7.1' "$TMPDIR/arguments" >/dev/null
grep -Fx -- 'GITBASE=https://github.com/biptec' "$TMPDIR/arguments" >/dev/null
grep -Fx -- 'GITPREFIX=opnsense-' "$TMPDIR/arguments" >/dev/null
for branch in TOOLSBRANCH COREBRANCH PLUGINSBRANCH PORTSBRANCH SRCBRANCH; do
    grep -Fx -- "$branch=master" "$TMPDIR/arguments" >/dev/null
done

grep -Fx -- '-C' "$TMPDIR/arguments" >/dev/null
grep -Fx -- "$BUILD_ROOT/tools" "$TMPDIR/arguments" >/dev/null
grep -Fx -- 'custom-vm,qcow2,24G,1G,proxmox' "$TMPDIR/arguments" >/dev/null
grep -E -- '^ADDITION=.*/emulators/qemu-guest-agent$' "$TMPDIR/arguments" >/dev/null
grep -E -- '^ADDITION=.*/sysutils/api-extensions$' "$TMPDIR/arguments" >/dev/null
grep -E -- '^ADDITION=.*/dns/bind$' "$TMPDIR/arguments" >/dev/null
grep -E -- '^ADDITION=.*/www/caddy$' "$TMPDIR/arguments" >/dev/null
grep -Fx -- "ADDITION=$EXPECTED_NOCLOUD" "$TMPDIR/arguments" >/dev/null
grep -Fx -- "ADDITION=$EXPECTED_CADDY_POLICY" "$TMPDIR/arguments" >/dev/null

python3 - "$MANIFEST" "$TOOLS_COMMIT" "$CORE_COMMIT" "$PLUGINS_COMMIT" "$PORTS_COMMIT" "$SRC_COMMIT" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
assert manifest["schema_version"] == 1
assert manifest["opnsense_version"] == "26.7.1"
assert manifest["image"] == {"size": "24G", "swap": "1G", "profile": "proxmox"}
for name, commit in zip(("tools", "core", "plugins", "ports", "src"), sys.argv[2:]):
    assert manifest["sources"][name] == {"branch": "master", "commit": commit}
PY

if BUILD_TEST_OUTPUT="$TMPDIR/failure-arguments" \
    BUILD_CONFIG="$TMPDIR/wrong-revisions.env" \
    BUILD_MANIFEST="$TMPDIR/failure-manifest.json" \
    PATH="$TMPDIR/bin:$PATH" \
    TOOLS_DIR="$BUILD_ROOT/tools" \
    CORE_DIR="$BUILD_ROOT/core" \
    PLUGINS_DIR="$BUILD_ROOT/plugins" \
    PORTS_DIR="$BUILD_ROOT/ports" \
    SRC_DIR="$BUILD_ROOT/src" \
    "$ROOT_DIR/image/build.sh" >"$TMPDIR/failure.out" 2>&1; then
    echo "build unexpectedly accepted a mismatched tools commit" >&2
    exit 1
fi
grep -F -- 'tools commit mismatch' "$TMPDIR/failure.out" >/dev/null

printf 'dirty\n' >> "$BUILD_ROOT/core/source.txt"
if BUILD_TEST_OUTPUT="$TMPDIR/dirty-arguments" \
    BUILD_CONFIG="$TMPDIR/source-revisions.env" \
    BUILD_MANIFEST="$TMPDIR/dirty-manifest.json" \
    PATH="$TMPDIR/bin:$PATH" \
    TOOLS_DIR="$BUILD_ROOT/tools" \
    CORE_DIR="$BUILD_ROOT/core" \
    PLUGINS_DIR="$BUILD_ROOT/plugins" \
    PORTS_DIR="$BUILD_ROOT/ports" \
    SRC_DIR="$BUILD_ROOT/src" \
    "$ROOT_DIR/image/build.sh" >"$TMPDIR/dirty.out" 2>&1; then
    echo "build unexpectedly accepted a dirty core checkout" >&2
    exit 1
fi
grep -F -- 'core repository is not clean' "$TMPDIR/dirty.out" >/dev/null
