#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

mkdir -p "$TMPDIR/bin" "$TMPDIR/tools"
cat > "$TMPDIR/bin/make" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$BUILD_TEST_OUTPUT"
EOF
chmod 755 "$TMPDIR/bin/make"

BUILD_TEST_OUTPUT="$TMPDIR/arguments" \
PATH="$TMPDIR/bin:$PATH" \
TOOLS_DIR="$TMPDIR/tools" \
IMAGE_SIZE="24G" \
IMAGE_SWAP="1G" \
"$ROOT_DIR/image/build.sh"

EXPECTED_PLUGIN="$ROOT_DIR/guest/nocloud-bootstrap"
grep -Fx -- '-C' "$TMPDIR/arguments" >/dev/null
grep -Fx -- "$TMPDIR/tools" "$TMPDIR/arguments" >/dev/null
grep -Fx -- 'custom-vm,qcow2,24G,1G,proxmox' "$TMPDIR/arguments" >/dev/null
grep -Fx -- "ADDITIONS=os-qemu-guest-agent os-caddy $EXPECTED_PLUGIN" "$TMPDIR/arguments" >/dev/null
