#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

mkdir -p "$TMPDIR/bin" "$TMPDIR/tools"
cat > "$TMPDIR/bin/make" <<'EOF'
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
} > "$BUILD_TEST_OUTPUT"
EOF
chmod 755 "$TMPDIR/bin/make"

BUILD_TEST_OUTPUT="$TMPDIR/arguments" \
PATH="$TMPDIR/bin:$PATH" \
TOOLS_DIR="$TMPDIR/tools" \
IMAGE_SIZE="24G" \
IMAGE_SWAP="1G" \
"$ROOT_DIR/image/build.sh"

EXPECTED_PLUGIN="$ROOT_DIR/guest/nocloud-bootstrap"
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
grep -Fx -- "$TMPDIR/tools" "$TMPDIR/arguments" >/dev/null
grep -Fx -- 'custom-vm,qcow2,24G,1G,proxmox' "$TMPDIR/arguments" >/dev/null
grep -Fx -- "ADDITIONS=os-qemu-guest-agent os-caddy $EXPECTED_PLUGIN $EXPECTED_CADDY_POLICY" "$TMPDIR/arguments" >/dev/null
